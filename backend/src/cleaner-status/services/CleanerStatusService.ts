import { CleanerPrivileges, CleanerProfile, CleanerStatus, CleanerStatusProgress, StatusConfig } from '../domain/types';

const STATUS_ORDER: CleanerStatus[] = ['NEWBIE', 'SPECIALIST', 'PROFESSIONAL', 'SUPERWOMAN', 'EXPERT'];
const STATUS_LABELS: Record<CleanerStatus, string> = {
  NEWBIE: 'Новичок',
  SPECIALIST: 'Специалист',
  PROFESSIONAL: 'Профессионал',
  SUPERWOMAN: 'Супервумен',
  EXPERT: 'Эксперт',
};

export class CleanerStatusService {
  evaluateCleanerStatus(cleaner: CleanerProfile, configs: StatusConfig[], now = new Date()): { status: CleanerStatus; reason: string } {
    if (cleaner.autoPromotionLocked) {
      return { status: cleaner.status, reason: 'auto_promotion_locked' };
    }

    const tenureDays = cleaner.workStartDate ? Math.floor((now.getTime() - new Date(cleaner.workStartDate).getTime()) / 86400000) : 0;
    const complaintRate = this.safeRate(cleaner.complaintsCount, cleaner.completedOrdersCount);
    const cancellationRate = this.safeRate(cleaner.cancellationCount, cleaner.completedOrdersCount);
    const lateRate = this.safeRate(cleaner.lateCount, cleaner.completedOrdersCount);

    let resolved: CleanerStatus = 'NEWBIE';
    for (const config of configs.sort((a, b) => STATUS_ORDER.indexOf(a.status) - STATUS_ORDER.indexOf(b.status))) {
      const rating = config.minRatingPeriodDays >= 90 ? cleaner.averageRating90d : cleaner.averageRating30d;
      const eligible =
        rating >= config.minRating &&
        cleaner.completedOrdersCount >= config.minCompletedOrders &&
        complaintRate <= config.maxComplaintsRate &&
        cancellationRate <= config.maxCancellationRate &&
        lateRate <= config.maxLateRate &&
        tenureDays >= config.minTenureDays;
      if (eligible) {
        resolved = config.status;
      }
    }

    return {
      status: resolved,
      reason: `rating30=${cleaner.averageRating30d};rating90=${cleaner.averageRating90d};tenureDays=${tenureDays};complaintRate=${complaintRate.toFixed(4)};cancellationRate=${cancellationRate.toFixed(4)};lateRate=${lateRate.toFixed(4)}`,
    };
  }

  getCleanerPrivileges(status: CleanerStatus): CleanerPrivileges {
    return {
      status,
      label: STATUS_LABELS[status],
      priorityOnHighAddonOrders: ['PROFESSIONAL', 'SUPERWOMAN', 'EXPERT'].includes(status),
      higherIncomeAccess: ['SUPERWOMAN', 'EXPERT'].includes(status),
      moreProfitableOrders: ['PROFESSIONAL', 'SUPERWOMAN', 'EXPERT'].includes(status),
    };
  }

  getProgressToNextStatus(cleaner: CleanerProfile, configs: StatusConfig[], now = new Date()): CleanerStatusProgress {
    const currentIndex = STATUS_ORDER.indexOf(cleaner.status);
    const nextStatus = currentIndex >= STATUS_ORDER.length - 1 ? null : STATUS_ORDER[currentIndex + 1];
    if (!nextStatus) {
      return {
        currentStatus: cleaner.status,
        nextStatus: null,
        daysRemaining: 0,
        requiredRating: null,
        ratingGap: 0,
        completedOrdersRemaining: 0,
        tenureDaysRemaining: 0,
        complaintRateGap: 0,
        cancellationRateGap: 0,
        lateRateGap: 0,
      };
    }

    const config = configs.find((item) => item.status === nextStatus)!;
    const tenureDays = cleaner.workStartDate ? Math.floor((now.getTime() - new Date(cleaner.workStartDate).getTime()) / 86400000) : 0;
    const complaintRate = this.safeRate(cleaner.complaintsCount, cleaner.completedOrdersCount);
    const cancellationRate = this.safeRate(cleaner.cancellationCount, cleaner.completedOrdersCount);
    const lateRate = this.safeRate(cleaner.lateCount, cleaner.completedOrdersCount);
    const rating = config.minRatingPeriodDays >= 90 ? cleaner.averageRating90d : cleaner.averageRating30d;

    return {
      currentStatus: cleaner.status,
      nextStatus,
      daysRemaining: Math.max(config.minRatingPeriodDays - Math.min(tenureDays, config.minRatingPeriodDays), 0),
      requiredRating: config.minRating,
      ratingGap: Math.max(config.minRating - rating, 0),
      completedOrdersRemaining: Math.max(config.minCompletedOrders - cleaner.completedOrdersCount, 0),
      tenureDaysRemaining: Math.max(config.minTenureDays - tenureDays, 0),
      complaintRateGap: Math.max(complaintRate - config.maxComplaintsRate, 0),
      cancellationRateGap: Math.max(cancellationRate - config.maxCancellationRate, 0),
      lateRateGap: Math.max(lateRate - config.maxLateRate, 0),
    };
  }

  private safeRate(value: number, total: number): number {
    if (total <= 0) return 0;
    return value / total;
  }
}
