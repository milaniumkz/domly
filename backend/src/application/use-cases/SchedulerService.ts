import { Cleaner, CleanerDayLoad, CleanerMonthlyStats } from '../../domain/entities/Cleaner';
import { FairnessScoreSnapshot } from '../../domain/entities/Assignment';
import { Order } from '../../domain/entities/Order';
import { CleanerSkillLevel } from '../../domain/enums/CleanerSkillLevel';
import { OrderStatus } from '../../domain/enums/OrderStatus';
import { AssignmentRepository } from '../../domain/repositories/AssignmentRepository';
import { CleanerRepository } from '../../domain/repositories/CleanerRepository';
import { OrderRepository } from '../../domain/repositories/OrderRepository';
import { UnitOfWork } from '../../domain/repositories/UnitOfWork';
import { Logger } from '../../infrastructure/logging/Logger';
import { monthKeyFromDate, overlaps } from '../../shared/Month';

export interface MonthContext {
  month: string;
  averageArea: number;
  averageHours: number;
  averageApartments: number;
}

export interface EligibleCleaner {
  cleaner: Cleaner;
  score: FairnessScoreSnapshot;
}

export class SchedulerService {
  constructor(
    private readonly cleaners: CleanerRepository,
    private readonly orders: OrderRepository,
    private readonly assignments: AssignmentRepository,
    private readonly uow: UnitOfWork,
    private readonly logger: Logger,
    private readonly random: () => number = Math.random,
  ) {}

  estimateCleaningDuration(area: number): number {
    if (area >= 30 && area < 50) return 2;
    if (area >= 50 && area < 75) return 3;
    if (area >= 75 && area < 100) return 4;
    if (area >= 100 && area < 150) return 5;
    if (area >= 150 && area < 200) return 6;
    if (area >= 200) return Math.max(7, Math.ceil(area / 35));
    return 1.5;
  }

  async getCleanerMonthlyStats(cleanerId: string, month: string): Promise<CleanerMonthlyStats> {
    return this.cleaners.getMonthlyStats(cleanerId, month);
  }

  async getEligibleCleaners(orderId: string): Promise<EligibleCleaner[]> {
    const order = await this.requireOrder(orderId);
    const allCleaners = await this.cleaners.getActiveCleaners();
    const monthContext = await this.buildMonthContext(allCleaners, monthKeyFromDate(order.date));
    const dayLoads = await this.cleaners.getDayLoads(order.date);

    return allCleaners
      .map((cleaner) => ({
        cleaner,
        score: this.calculateCleanerFairnessScore(cleaner, order, monthContext, dayLoads.get(cleaner.id)),
      }))
      .filter((candidate) => candidate.score.fitsTimeWindow && candidate.score.fitsDailyLimit)
      .sort((a, b) => a.score.totalScore - b.score.totalScore);
  }

  calculateCleanerFairnessScore(
    cleaner: Cleaner,
    order: Order,
    monthContext: MonthContext,
    dayLoad?: CleanerDayLoad,
  ): FairnessScoreSnapshot {
    const currentDayLoad = dayLoad ?? {
      cleanerId: cleaner.id,
      date: order.date,
      assignedArea: 0,
      assignedHours: 0,
      assignedApartments: 0,
      intervals: [],
    };

    const projectedArea = cleaner.monthlyAssignedArea + order.area;
    const projectedHours = cleaner.monthlyAssignedHours + order.estimatedDurationHours;
    const projectedApartments = cleaner.monthlyAssignedApartments + 1;
    const dayProjectedHours = currentDayLoad.assignedHours + order.estimatedDurationHours;
    const dayProjectedArea = currentDayLoad.assignedArea + order.area;
    const fitsDailyLimit = dayProjectedHours <= cleaner.dailyWorkLimitHours;
    const fitsTimeWindow = !currentDayLoad.intervals.some((interval) =>
      overlaps(interval.startTime, interval.endTime, order.startTime, order.endTime)
    );

    const monthlyAreaScore = monthContext.averageArea <= 0
      ? 0
      : projectedArea / monthContext.averageArea;
    const monthlyHoursScore = monthContext.averageHours <= 0
      ? 0
      : projectedHours / monthContext.averageHours;
    const monthlyApartmentsScore = monthContext.averageApartments <= 0
      ? 0
      : projectedApartments / monthContext.averageApartments;

    // Daily target is soft: under 200 m² gets a bonus, overfilled days get penalized.
    const dailyTargetGap = Math.max(200 - dayProjectedArea, 0);
    const dailyTargetScore = dayProjectedArea >= 200
      ? 1 + ((dayProjectedArea - 200) / 200)
      : 0.7 - Math.min(dailyTargetGap / 400, 0.4);

    const districtScore = cleaner.preferredZones.includes(order.district) ? 0.75 : 1.15;
    const skillMultiplier = this.skillMultiplier(cleaner.skillLevel, order.area);
    const randomScore = this.random() * 0.08;

    const reasons = [
      `monthly_area=${projectedArea.toFixed(2)}`,
      `monthly_hours=${projectedHours.toFixed(2)}`,
      `monthly_apartments=${projectedApartments}`,
      `day_area=${dayProjectedArea.toFixed(2)}`,
      `day_hours=${dayProjectedHours.toFixed(2)}`,
      cleaner.preferredZones.includes(order.district) ? 'preferred_zone' : 'non_preferred_zone',
      `skill=${cleaner.skillLevel}`,
    ];

    const totalScore =
      monthlyAreaScore * 0.34 +
      monthlyHoursScore * 0.34 +
      monthlyApartmentsScore * 0.12 +
      dailyTargetScore * 0.10 +
      districtScore * 0.06 +
      skillMultiplier * 0.04 +
      randomScore;

    return {
      totalScore,
      monthlyAreaScore,
      monthlyHoursScore,
      monthlyApartmentsScore,
      dayLoadScore: dayProjectedHours,
      dailyTargetScore,
      districtScore,
      skillScore: skillMultiplier,
      randomScore,
      fitsTimeWindow,
      fitsDailyLimit,
      reasons,
    };
  }

  async assignOrdersForDay(date: string): Promise<Array<{ orderId: string; cleanerId: string | null; reason: string[] }>> {
    return this.uow.transaction(async () => {
      const orders = await this.orders.getUnassignedOrdersForDay(date);
      const allCleaners = await this.cleaners.getActiveCleaners();
      const monthContext = await this.buildMonthContext(allCleaners, monthKeyFromDate(date));
      const dayLoads = await this.cleaners.getDayLoads(date);
      const results: Array<{ orderId: string; cleanerId: string | null; reason: string[] }> = [];

      for (const order of orders) {
        const eligible = allCleaners
          .map((cleaner) => {
            const score = this.calculateCleanerFairnessScore(cleaner, order, monthContext, dayLoads.get(cleaner.id));
            return { cleaner, score };
          })
          .filter((candidate) => candidate.score.fitsDailyLimit && candidate.score.fitsTimeWindow)
          .sort((a, b) => a.score.totalScore - b.score.totalScore);

        if (eligible.length === 0) {
          results.push({ orderId: order.id, cleanerId: null, reason: ['no_eligible_cleaners'] });
          continue;
        }

        const selected = this.pickWeightedCandidate(eligible.slice(0, Math.min(3, eligible.length)));
        await this.assignOne(order, selected.cleaner, selected.score, dayLoads);
        results.push({ orderId: order.id, cleanerId: selected.cleaner.id, reason: selected.score.reasons });
      }

      return results;
    });
  }

  async rebalanceAssignments(date: string): Promise<Array<{ orderId: string; cleanerId: string | null; reason: string[] }>> {
    return this.uow.transaction(async () => {
      const allOrders = await this.orders.getOrdersForDay(date);
      const rebalanceable = allOrders.filter((order) => order.status === OrderStatus.ASSIGNED);

      for (const order of rebalanceable) {
        if (order.cleanerId) {
          await this.cleaners.applyAssignmentImpact(order.cleanerId, -order.area, -order.estimatedDurationHours, -1);
        }
        await this.assignments.deleteByOrderId(order.id);
        await this.orders.clearCleaner(order.id);
      }

      return this.assignOrdersForDay(date);
    });
  }

  async reassignCancelledOrder(orderId: string): Promise<Array<{ orderId: string; cleanerId: string | null; reason: string[] }>> {
    return this.uow.transaction(async () => {
      const order = await this.requireOrder(orderId);
      if (order.cleanerId) {
        await this.cleaners.applyAssignmentImpact(order.cleanerId, -order.area, -order.estimatedDurationHours, -1);
      }
      await this.assignments.deleteByOrderId(orderId);
      await this.orders.clearCleaner(orderId);
      await this.orders.setStatus(orderId, OrderStatus.CANCELLED);
      return this.assignOrdersForDay(order.date);
    });
  }

  private async assignOne(
    order: Order,
    cleaner: Cleaner,
    snapshot: FairnessScoreSnapshot,
    dayLoads: Map<string, CleanerDayLoad>,
  ): Promise<void> {
    await this.orders.setCleaner(order.id, cleaner.id);
    await this.assignments.upsert(order.id, cleaner.id, snapshot, false);
    await this.cleaners.applyAssignmentImpact(cleaner.id, order.area, order.estimatedDurationHours, 1);

    const current = dayLoads.get(cleaner.id) ?? {
      cleanerId: cleaner.id,
      date: order.date,
      assignedArea: 0,
      assignedHours: 0,
      assignedApartments: 0,
      intervals: [],
    };
    current.assignedArea += order.area;
    current.assignedHours += order.estimatedDurationHours;
    current.assignedApartments += 1;
    current.intervals.push({ startTime: order.startTime, endTime: order.endTime });
    dayLoads.set(cleaner.id, current);

    cleaner.monthlyAssignedArea += order.area;
    cleaner.monthlyAssignedHours += order.estimatedDurationHours;
    cleaner.monthlyAssignedApartments += 1;

    this.logger.info('order_assigned', {
      orderId: order.id,
      cleanerId: cleaner.id,
      score: snapshot.totalScore,
      reasons: snapshot.reasons,
    });
  }

  private pickWeightedCandidate(candidates: Array<{ cleaner: Cleaner; score: FairnessScoreSnapshot }>) {
    const weights = candidates.map((candidate) => 1 / Math.max(candidate.score.totalScore, 0.0001));
    const totalWeight = weights.reduce((sum, weight) => sum + weight, 0);
    let pivot = this.random() * totalWeight;
    for (let index = 0; index < candidates.length; index += 1) {
      pivot -= weights[index];
      if (pivot <= 0) {
        return candidates[index];
      }
    }
    return candidates[0];
  }

  private async buildMonthContext(cleaners: Cleaner[], month: string): Promise<MonthContext> {
    if (cleaners.length === 0) {
      return { month, averageArea: 0, averageHours: 0, averageApartments: 0 };
    }
    const cleanerIds = cleaners.map((cleaner) => cleaner.id);
    const stats = await this.cleaners.getMonthlyStatsBulk(cleanerIds, month);

    let totalArea = 0;
    let totalHours = 0;
    let totalApartments = 0;
    for (const cleaner of cleaners) {
      const stat = stats.get(cleaner.id) ?? {
        cleanerId: cleaner.id,
        month,
        assignedArea: cleaner.monthlyAssignedArea,
        assignedHours: cleaner.monthlyAssignedHours,
        assignedApartments: cleaner.monthlyAssignedApartments,
      };
      totalArea += stat.assignedArea;
      totalHours += stat.assignedHours;
      totalApartments += stat.assignedApartments;
    }

    return {
      month,
      averageArea: totalArea / cleaners.length,
      averageHours: totalHours / cleaners.length,
      averageApartments: totalApartments / cleaners.length,
    };
  }

  private skillMultiplier(skill: CleanerSkillLevel, area: number): number {
    if (area < 100) return 1;
    switch (skill) {
      case CleanerSkillLevel.EXPERT:
        return 0.85;
      case CleanerSkillLevel.SENIOR:
        return 0.92;
      case CleanerSkillLevel.MIDDLE:
        return 1.0;
      case CleanerSkillLevel.JUNIOR:
      default:
        return 1.12;
    }
  }

  private async requireOrder(orderId: string): Promise<Order> {
    const order = await this.orders.getById(orderId);
    if (!order) {
      throw new Error(`Order ${orderId} not found`);
    }
    return order;
  }
}
