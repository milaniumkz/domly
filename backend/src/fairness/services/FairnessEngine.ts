import {
  CleanerAssignmentScore,
  CleanerCandidate,
  CleanerMonthlyStats,
  FairnessConfig,
  FairnessOrder,
  MonthlyFairnessReport,
  MonthlyTargets,
} from '../domain/types';

export const DEFAULT_FAIRNESS_CONFIG: FairnessConfig = {
  weightArea: 0.24,
  weightHours: 0.24,
  weightApartments: 0.14,
  weightIncome: 0.20,
  weightTravel: 0.08,
  weightDayCapacity: 0.05,
  weightSizePenalty: 0.03,
  weightPriority: 0.02,
  randomnessFactor: 0.08,
  largeApartmentThreshold: 100,
  targetDailyArea: 200,
};

export class FairnessEngine {
  constructor(private readonly config: FairnessConfig = DEFAULT_FAIRNESS_CONFIG) {}

  calculateMonthlyTargets(month: string, orders: FairnessOrder[], cleaners: CleanerCandidate[]): MonthlyTargets {
    const cleanersCount = Math.max(cleaners.length, 1);
    const totals = orders.reduce(
      (acc, order) => {
        acc.area += order.area;
        acc.hours += order.estimatedHours;
        acc.apartments += order.apartmentsCount;
        acc.income += order.income;
        return acc;
      },
      { area: 0, hours: 0, apartments: 0, income: 0 },
    );

    return {
      month,
      targetArea: totals.area / cleanersCount,
      targetHours: totals.hours / cleanersCount,
      targetApartments: totals.apartments / cleanersCount,
      targetIncome: totals.income / cleanersCount,
    };
  }

  computeCleanerAssignmentScore(
    cleaner: CleanerCandidate,
    order: FairnessOrder,
    stats: CleanerMonthlyStats,
    targets: MonthlyTargets,
  ): CleanerAssignmentScore {
    const projectedArea = stats.totalArea + order.area;
    const projectedHours = stats.totalHours + order.estimatedHours;
    const projectedApartments = stats.totalApartments + order.apartmentsCount;
    const projectedIncome = stats.totalIncome + order.income;
    const projectedDayHours = cleaner.dayAssignedHours + order.estimatedHours;
    const projectedDayArea = cleaner.dayAssignedArea + order.area;

    const deviationArea = this.relativeDeviation(projectedArea, targets.targetArea);
    const deviationHours = this.relativeDeviation(projectedHours, targets.targetHours);
    const deviationApartments = this.relativeDeviation(projectedApartments, targets.targetApartments);
    const deviationIncome = this.relativeDeviation(projectedIncome, targets.targetIncome);

    const currentDayRemainingCapacity = Math.max(cleaner.dailyWorkLimitHours - projectedDayHours, 0);
    const capacityPenalty = projectedDayHours > cleaner.dailyWorkLimitHours
      ? 10
      : 1 - Math.min(currentDayRemainingCapacity / Math.max(cleaner.dailyWorkLimitHours, 1), 1);

    const travelCost = order.travelCostByCleaner?.[cleaner.id] ?? cleaner.averageTravelCost ?? 0;
    const priority = cleaner.cleanerPriorityPenaltyOrBonus ?? 0;

    const largeObjectPenalty = this.computeLargeObjectPenalty(order, stats);
    const fairnessCoefficient =
      deviationArea * this.config.weightArea +
      deviationHours * this.config.weightHours +
      deviationApartments * this.config.weightApartments +
      deviationIncome * this.config.weightIncome +
      capacityPenalty * this.config.weightDayCapacity +
      travelCost * this.config.weightTravel +
      largeObjectPenalty * this.config.weightSizePenalty +
      priority * this.config.weightPriority;

    const weightedRandomScore = Math.random() * this.config.randomnessFactor;
    const totalScore = fairnessCoefficient + weightedRandomScore;

    return {
      cleanerId: cleaner.id,
      totalScore,
      fairnessCoefficient,
      weightedRandomScore,
      components: {
        deviationFromMonthlyTargetArea: deviationArea,
        deviationFromMonthlyTargetHours: deviationHours,
        deviationFromMonthlyTargetApartments: deviationApartments,
        deviationFromMonthlyTargetIncome: deviationIncome,
        currentDayRemainingCapacity: capacityPenalty,
        travelCost,
        cleanerPriorityPenaltyOrBonus: priority,
        largeObjectPenalty,
      },
      explain: [
        `projected_area=${projectedArea.toFixed(2)}`,
        `projected_hours=${projectedHours.toFixed(2)}`,
        `projected_apartments=${projectedApartments.toFixed(0)}`,
        `projected_income=${projectedIncome.toFixed(2)}`,
        `projected_day_area=${projectedDayArea.toFixed(2)}`,
        `projected_day_hours=${projectedDayHours.toFixed(2)}`,
        `travel_cost=${travelCost.toFixed(4)}`,
        `priority=${priority.toFixed(4)}`,
        `large_penalty=${largeObjectPenalty.toFixed(4)}`,
      ],
    };
  }

  assignOrderWithFairness(
    order: FairnessOrder,
    cleaners: CleanerCandidate[],
    statsMap: Map<string, CleanerMonthlyStats>,
    targets: MonthlyTargets,
  ): { cleaner: CleanerCandidate; score: CleanerAssignmentScore; ranked: CleanerAssignmentScore[] } {
    const ranked = cleaners
      .map((cleaner) => this.computeCleanerAssignmentScore(cleaner, order, statsMap.get(cleaner.id) ?? this.emptyStats(cleaner.id, order.month), targets))
      .sort((a, b) => a.totalScore - b.totalScore);

    const top = ranked.slice(0, Math.min(3, ranked.length));
    const chosen = this.pickWeighted(top);
    const cleaner = cleaners.find((item) => item.id === chosen.cleanerId);
    if (!cleaner) {
      throw new Error('No cleaner selected');
    }

    return { cleaner, score: chosen, ranked };
  }

  generateMonthlyFairnessReport(
    month: string,
    stats: CleanerMonthlyStats[],
    targets: MonthlyTargets,
  ): MonthlyFairnessReport {
    return {
      month,
      targets,
      cleaners: stats.map((item) => ({
        cleanerId: item.cleanerId,
        totalArea: item.totalArea,
        totalHours: item.totalHours,
        totalApartments: item.totalApartments,
        totalIncome: item.totalIncome,
        fairnessCoefficient: this.computeReportCoefficient(item, targets),
        deviationArea: this.relativeDeviation(item.totalArea, targets.targetArea),
        deviationHours: this.relativeDeviation(item.totalHours, targets.targetHours),
        deviationApartments: this.relativeDeviation(item.totalApartments, targets.targetApartments),
        deviationIncome: this.relativeDeviation(item.totalIncome, targets.targetIncome),
        largeApartmentCount: item.largeApartmentCount,
        smallApartmentCount: item.smallApartmentCount,
      })),
    };
  }

  simulateAssignments(
    month: string,
    orders: FairnessOrder[],
    cleaners: CleanerCandidate[],
    initialStats: CleanerMonthlyStats[],
  ) {
    const targets = this.calculateMonthlyTargets(month, orders, cleaners);
    const statsMap = new Map(initialStats.map((item) => [item.cleanerId, { ...item }]));
    const dayState = new Map(cleaners.map((cleaner) => [cleaner.id, { ...cleaner }]));
    const decisions = [] as Array<{
      orderId: string;
      cleanerId: string;
      score: CleanerAssignmentScore;
      explain: string[];
    }>;

    for (const order of orders) {
      const decision = this.assignOrderWithFairness(
        order,
        Array.from(dayState.values()),
        statsMap,
        targets,
      );

      decisions.push({
        orderId: order.id,
        cleanerId: decision.cleaner.id,
        score: decision.score,
        explain: decision.score.explain,
      });

      const cleanerState = dayState.get(decision.cleaner.id)!;
      cleanerState.dayAssignedHours += order.estimatedHours;
      cleanerState.dayAssignedArea += order.area;
      cleanerState.dayAssignedApartments += order.apartmentsCount;

      const stats = statsMap.get(decision.cleaner.id) ?? this.emptyStats(decision.cleaner.id, month);
      stats.totalArea += order.area;
      stats.totalHours += order.estimatedHours;
      stats.totalApartments += order.apartmentsCount;
      stats.totalIncome += order.income;
      if (order.area >= this.config.largeApartmentThreshold) {
        stats.largeApartmentCount += 1;
      } else {
        stats.smallApartmentCount += 1;
      }
      statsMap.set(decision.cleaner.id, stats);
    }

    return {
      month,
      targets,
      decisions,
      report: this.generateMonthlyFairnessReport(month, Array.from(statsMap.values()), targets),
    };
  }

  private computeLargeObjectPenalty(order: FairnessOrder, stats: CleanerMonthlyStats): number {
    if (order.area < this.config.largeApartmentThreshold) {
      const imbalance = Math.max(stats.smallApartmentCount - stats.largeApartmentCount, 0);
      return imbalance / Math.max(stats.smallApartmentCount + stats.largeApartmentCount, 1);
    }
    const imbalance = Math.max(stats.largeApartmentCount - stats.smallApartmentCount, 0);
    return imbalance / Math.max(stats.smallApartmentCount + stats.largeApartmentCount, 1);
  }

  private computeReportCoefficient(stats: CleanerMonthlyStats, targets: MonthlyTargets): number {
    return (
      this.relativeDeviation(stats.totalArea, targets.targetArea) * this.config.weightArea +
      this.relativeDeviation(stats.totalHours, targets.targetHours) * this.config.weightHours +
      this.relativeDeviation(stats.totalApartments, targets.targetApartments) * this.config.weightApartments +
      this.relativeDeviation(stats.totalIncome, targets.targetIncome) * this.config.weightIncome
    );
  }

  private relativeDeviation(value: number, target: number): number {
    if (target <= 0) return 0;
    return Math.abs(value - target) / target;
  }

  private emptyStats(cleanerId: string, month: string): CleanerMonthlyStats {
    return {
      cleanerId,
      month,
      totalArea: 0,
      totalHours: 0,
      totalApartments: 0,
      totalIncome: 0,
      largeApartmentCount: 0,
      smallApartmentCount: 0,
    };
  }

  private pickWeighted(scores: CleanerAssignmentScore[]): CleanerAssignmentScore {
    const weights = scores.map((score) => 1 / Math.max(score.totalScore, 0.0001));
    const total = weights.reduce((sum, weight) => sum + weight, 0);
    let pivot = Math.random() * total;
    for (let index = 0; index < scores.length; index += 1) {
      pivot -= weights[index];
      if (pivot <= 0) return scores[index];
    }
    return scores[0];
  }
}
