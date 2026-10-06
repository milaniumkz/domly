import { timeToMinutes } from '../../shared/Month';
import {
  AddonPriorityType,
  AssignmentConfig,
  CleanerAddonPriorityScore,
  CleanerMonthlyStats,
  CleanerProfile,
  CleanerStatus,
  OrderAddonPriorityContext,
} from '../domain/types';

const STATUS_PRIORITY: Record<CleanerStatus, number> = {
  NEWBIE: 1,
  SPECIALIST: 2,
  PROFESSIONAL: 3,
  SUPERWOMAN: 4,
  EXPERT: 5,
};

export class AddonPriorityAssignmentService {
  classifyOrderByAddonValue(order: OrderAddonPriorityContext, config: AssignmentConfig): AddonPriorityType {
    if (order.addonTotalPrice >= config.highAddonThreshold) return 'HIGH_ADDON';
    if (order.addonTotalPrice >= config.mediumAddonThreshold) return 'MEDIUM_ADDON';
    if (order.addonTotalPrice > 0) return 'LOW_ADDON';
    return 'NO_ADDON';
  }

  calculateCleanerAddonPriorityScore(
    cleaner: CleanerProfile,
    order: OrderAddonPriorityContext,
    monthlyStats: CleanerMonthlyStats,
    config: AssignmentConfig,
    options: {
      averageAddonIncome: number;
      averageHours: number;
      averageArea: number;
      dayAssignedHours: number;
      districtDistanceScore: number;
      hasTimeConflict: boolean;
    },
  ): CleanerAddonPriorityScore {
    const priorityType = this.classifyOrderByAddonValue(order, config);
    const statusPriorityScore = priorityType === 'HIGH_ADDON'
      ? (6 - STATUS_PRIORITY[cleaner.status]) / 5
      : 0;
    const addonBalanceScore = this.relativeDeviation(monthlyStats.addonIncome, options.averageAddonIncome);
    const hoursBalanceScore = this.relativeDeviation(monthlyStats.totalHours, options.averageHours);
    const areaBalanceScore = this.relativeDeviation(monthlyStats.totalArea, options.averageArea);
    const fairnessScore = this.relativeDeviation(monthlyStats.totalIncome, options.averageAddonIncome + options.averageHours + options.averageArea);
    const distanceScore = options.districtDistanceScore;
    const overloadPenalty = (options.dayAssignedHours + order.estimatedDurationHours) > cleaner.dailyWorkLimitHours ? 10 : 0;
    const conflictPenalty = options.hasTimeConflict ? 10 : 0;
    const randomnessScore = Math.random() * config.randomnessFactor;

    const totalScore =
      statusPriorityScore * config.weightStatusPriority +
      fairnessScore * config.weightFairness +
      addonBalanceScore * config.weightMonthlyAddonBalance +
      hoursBalanceScore * config.weightHoursBalance +
      areaBalanceScore * config.weightAreaBalance +
      distanceScore * config.weightDistance +
      overloadPenalty +
      conflictPenalty +
      randomnessScore;

    return {
      cleanerId: cleaner.id,
      orderId: order.id,
      addonPriorityType: priorityType,
      totalScore,
      statusPriorityScore,
      fairnessScore,
      addonBalanceScore,
      hoursBalanceScore,
      areaBalanceScore,
      distanceScore,
      randomnessScore,
      reasons: [
        `priority_type=${priorityType}`,
        `status=${cleaner.status}`,
        `status_score=${statusPriorityScore.toFixed(4)}`,
        `addon_income=${monthlyStats.addonIncome.toFixed(2)}`,
        `hours=${monthlyStats.totalHours.toFixed(2)}`,
        `area=${monthlyStats.totalArea.toFixed(2)}`,
        `distance=${distanceScore.toFixed(4)}`,
        `overload_penalty=${overloadPenalty.toFixed(4)}`,
        `conflict_penalty=${conflictPenalty.toFixed(4)}`,
      ],
    };
  }

  isEligibleCleaner(
    cleaner: CleanerProfile,
    order: OrderAddonPriorityContext,
    context: { dayAssignedHours: number; hasTimeConflict: boolean },
  ): boolean {
    if (!cleaner.active) return false;
    if (cleaner.district && cleaner.district !== order.district) return false;
    if (context.hasTimeConflict) return false;
    return context.dayAssignedHours + order.estimatedDurationHours <= cleaner.dailyWorkLimitHours;
  }

  private relativeDeviation(value: number, target: number): number {
    if (target <= 0) return 0;
    return Math.abs(value - target) / target;
  }

  hasTimeConflict(order: OrderAddonPriorityContext, dayIntervals: Array<{ startTime: string; endTime: string }>): boolean {
    const start = timeToMinutes(order.startTime);
    const end = timeToMinutes(order.endTime);
    return dayIntervals.some((interval) => {
      const intervalStart = timeToMinutes(interval.startTime);
      const intervalEnd = timeToMinutes(interval.endTime);
      return start < intervalEnd && intervalStart < end;
    });
  }
}
