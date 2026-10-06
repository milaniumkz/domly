export type CleanerStatus = 'NEWBIE' | 'SPECIALIST' | 'PROFESSIONAL' | 'SUPERWOMAN' | 'EXPERT';
export type AddonPriorityType = 'HIGH_ADDON' | 'MEDIUM_ADDON' | 'LOW_ADDON' | 'NO_ADDON';

export interface CleanerProfile {
  id: string;
  name: string;
  status: CleanerStatus;
  currentRating: number;
  averageRating30d: number;
  averageRating90d: number;
  workStartDate: string | null;
  completedOrdersCount: number;
  complaintsCount: number;
  cancellationCount: number;
  lateCount: number;
  active: boolean;
  district: string | null;
  dailyWorkLimitHours: number;
  autoPromotionLocked: boolean;
}

export interface CleanerStatusHistoryEntry {
  id: string;
  cleanerId: string;
  oldStatus: CleanerStatus | null;
  newStatus: CleanerStatus;
  reason: string;
  createdAt: string;
}

export interface CleanerMonthlyStats {
  cleanerId: string;
  month: string;
  totalArea: number;
  totalHours: number;
  totalOrders: number;
  totalIncome: number;
  addonIncome: number;
  highAddonOrdersCount: number;
  mediumAddonOrdersCount: number;
  lowAddonOrdersCount: number;
}

export interface StatusConfig {
  status: CleanerStatus;
  minRating: number;
  minRatingPeriodDays: number;
  minCompletedOrders: number;
  maxComplaintsRate: number;
  maxCancellationRate: number;
  maxLateRate: number;
  minTenureDays: number;
}

export interface AssignmentConfig {
  highAddonThreshold: number;
  mediumAddonThreshold: number;
  weightStatusPriority: number;
  weightFairness: number;
  weightMonthlyAddonBalance: number;
  weightHoursBalance: number;
  weightAreaBalance: number;
  weightDistance: number;
  randomnessFactor: number;
}

export interface OrderAddonPriorityContext {
  id: string;
  date: string;
  startTime: string;
  endTime: string;
  area: number;
  basePrice: number;
  addonTotalPrice: number;
  totalPrice: number;
  estimatedDurationHours: number;
  district: string;
  status: string;
}

export interface CleanerStatusProgress {
  currentStatus: CleanerStatus;
  nextStatus: CleanerStatus | null;
  daysRemaining: number;
  requiredRating: number | null;
  ratingGap: number;
  completedOrdersRemaining: number;
  tenureDaysRemaining: number;
  complaintRateGap: number;
  cancellationRateGap: number;
  lateRateGap: number;
}

export interface CleanerPrivileges {
  status: CleanerStatus;
  label: string;
  priorityOnHighAddonOrders: boolean;
  higherIncomeAccess: boolean;
  moreProfitableOrders: boolean;
}

export interface CleanerAddonPriorityScore {
  cleanerId: string;
  orderId: string;
  addonPriorityType: AddonPriorityType;
  totalScore: number;
  statusPriorityScore: number;
  fairnessScore: number;
  addonBalanceScore: number;
  hoursBalanceScore: number;
  areaBalanceScore: number;
  distanceScore: number;
  randomnessScore: number;
  reasons: string[];
}
