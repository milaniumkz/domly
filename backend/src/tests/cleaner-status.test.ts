import test from 'node:test';
import assert from 'node:assert/strict';
import { CleanerStatusService } from '../cleaner-status/services/CleanerStatusService';
import { AddonPriorityAssignmentService } from '../cleaner-status/services/AddonPriorityAssignmentService';
import { AssignmentConfig, CleanerMonthlyStats, CleanerProfile, StatusConfig } from '../cleaner-status/domain/types';

const configs: StatusConfig[] = [
  { status: 'NEWBIE', minRating: 0, minRatingPeriodDays: 0, minCompletedOrders: 0, maxComplaintsRate: 1, maxCancellationRate: 1, maxLateRate: 1, minTenureDays: 0 },
  { status: 'SPECIALIST', minRating: 4.5, minRatingPeriodDays: 0, minCompletedOrders: 10, maxComplaintsRate: 0.10, maxCancellationRate: 0.10, maxLateRate: 0.10, minTenureDays: 14 },
  { status: 'PROFESSIONAL', minRating: 4.9, minRatingPeriodDays: 30, minCompletedOrders: 30, maxComplaintsRate: 0.05, maxCancellationRate: 0.05, maxLateRate: 0.05, minTenureDays: 30 },
  { status: 'SUPERWOMAN', minRating: 4.9, minRatingPeriodDays: 90, minCompletedOrders: 80, maxComplaintsRate: 0.03, maxCancellationRate: 0.03, maxLateRate: 0.03, minTenureDays: 90 },
  { status: 'EXPERT', minRating: 4.9, minRatingPeriodDays: 90, minCompletedOrders: 200, maxComplaintsRate: 0.01, maxCancellationRate: 0.02, maxLateRate: 0.02, minTenureDays: 365 },
];

const assignmentConfig: AssignmentConfig = {
  highAddonThreshold: 10000,
  mediumAddonThreshold: 5000,
  weightStatusPriority: 0.34,
  weightFairness: 0.24,
  weightMonthlyAddonBalance: 0.16,
  weightHoursBalance: 0.10,
  weightAreaBalance: 0.08,
  weightDistance: 0.04,
  randomnessFactor: 0.04,
};

test('evaluateCleanerStatus returns EXPERT for top cleaner', () => {
  const service = new CleanerStatusService();
  const cleaner: CleanerProfile = {
    id: 'c1',
    name: 'Asem',
    status: 'SUPERWOMAN',
    currentRating: 5,
    averageRating30d: 4.95,
    averageRating90d: 4.93,
    workStartDate: '2024-01-01',
    completedOrdersCount: 260,
    complaintsCount: 1,
    cancellationCount: 2,
    lateCount: 2,
    active: true,
    district: 'center',
    dailyWorkLimitHours: 8,
    autoPromotionLocked: false,
  };
  const result = service.evaluateCleanerStatus(cleaner, configs, new Date('2026-04-01'));
  assert.equal(result.status, 'EXPERT');
});

test('progress to next status reports remaining requirements', () => {
  const service = new CleanerStatusService();
  const cleaner: CleanerProfile = {
    id: 'c2',
    name: 'Dana',
    status: 'SPECIALIST',
    currentRating: 4.8,
    averageRating30d: 4.8,
    averageRating90d: 4.7,
    workStartDate: '2026-02-15',
    completedOrdersCount: 12,
    complaintsCount: 1,
    cancellationCount: 0,
    lateCount: 0,
    active: true,
    district: 'center',
    dailyWorkLimitHours: 8,
    autoPromotionLocked: false,
  };
  const progress = service.getProgressToNextStatus(cleaner, configs, new Date('2026-03-01'));
  assert.equal(progress.nextStatus, 'PROFESSIONAL');
  assert.ok(progress.ratingGap > 0);
  assert.ok(progress.completedOrdersRemaining > 0);
});

test('high addon order prefers higher status under equal load', () => {
  const service = new AddonPriorityAssignmentService();
  const expert: CleanerProfile = {
    id: 'expert', name: 'Expert', status: 'EXPERT', currentRating: 5, averageRating30d: 5, averageRating90d: 5,
    workStartDate: '2024-01-01', completedOrdersCount: 300, complaintsCount: 0, cancellationCount: 0, lateCount: 0,
    active: true, district: 'center', dailyWorkLimitHours: 8, autoPromotionLocked: false,
  };
  const specialist: CleanerProfile = { ...expert, id: 'specialist', status: 'SPECIALIST' };
  const stats: CleanerMonthlyStats = {
    cleanerId: 'expert', month: '2026-03', totalArea: 200, totalHours: 20, totalOrders: 10, totalIncome: 50000,
    addonIncome: 10000, highAddonOrdersCount: 2, mediumAddonOrdersCount: 1, lowAddonOrdersCount: 1,
  };
  const order = {
    id: 'o1', date: '2026-03-12', startTime: '10:00', endTime: '13:00', area: 60, basePrice: 10000,
    addonTotalPrice: 12000, totalPrice: 22000, estimatedDurationHours: 3, district: 'center', status: 'PENDING',
  };
  const expertScore = service.calculateCleanerAddonPriorityScore(expert, order, stats, assignmentConfig, {
    averageAddonIncome: 12000, averageHours: 25, averageArea: 240, dayAssignedHours: 1, districtDistanceScore: 0, hasTimeConflict: false,
  });
  const specialistScore = service.calculateCleanerAddonPriorityScore(specialist, order, stats, assignmentConfig, {
    averageAddonIncome: 12000, averageHours: 25, averageArea: 240, dayAssignedHours: 1, districtDistanceScore: 0, hasTimeConflict: false,
  });
  assert.ok(expertScore.totalScore < specialistScore.totalScore);
});
