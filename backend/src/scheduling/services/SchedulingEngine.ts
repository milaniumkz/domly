import { SchedulerService } from '../../application/use-cases/SchedulerService';
import { CalendarBookingService } from '../../calendar/services/CalendarBookingService';
import { CustomPackageService } from '../../custom-package/services/CustomPackageService';
import { CleanerCandidate, CleanerMonthlyStats, FairnessOrder } from '../../fairness/domain/types';
import { FairnessEngine } from '../../fairness/services/FairnessEngine';
import { AssignmentDecision, AvailabilityQuery, ManualOverrideCommand, SchedulingRequest } from '../domain/types';
import { DurationEstimator } from './DurationEstimator';
import { ManualOverrideManager } from './ManualOverrideManager';
import { ReportingModule } from './ReportingModule';

export class SchedulingEngine {
  constructor(
    private readonly durationEstimator: DurationEstimator,
    private readonly calendarBookingService: CalendarBookingService,
    private readonly schedulerService: SchedulerService,
    private readonly fairnessEngine: FairnessEngine,
    private readonly customPackageService: CustomPackageService,
    private readonly manualOverrideManager: ManualOverrideManager,
    private readonly reportingModule: ReportingModule,
  ) {}

  estimateDuration(area: number) {
    return this.durationEstimator.estimate(area);
  }

  async getAvailabilityCalendar(query: AvailabilityQuery) {
    return this.calendarBookingService.getAvailableDates('system', query.apartmentId, query.packageId ?? '', query.month);
  }

  async bookSchedule(userPackageId: string, selectedDatesWithTime: Array<{ date: string; startTime: string; endTime: string }>) {
    return this.calendarBookingService.bookPackageSchedule(userPackageId, selectedDatesWithTime);
  }

  async assignOrdersForDay(date: string): Promise<AssignmentDecision[]> {
    const results = await this.schedulerService.assignOrdersForDay(date);
    return results.map((item) => ({
      orderId: item.orderId,
      cleanerId: item.cleanerId,
      totalScore: null,
      explain: item.reason,
      assignedAt: new Date().toISOString(),
      mode: 'AUTO',
    }));
  }

  async assignOrderWithFairness(
    order: FairnessOrder,
    cleaners: CleanerCandidate[],
    stats: CleanerMonthlyStats[],
  ) {
    const targets = this.fairnessEngine.calculateMonthlyTargets(order.month, [order], cleaners);
    return this.fairnessEngine.assignOrderWithFairness(order, cleaners, new Map(stats.map((item) => [item.cleanerId, item])), targets);
  }

  async buildCustomPackage(input: Parameters<CustomPackageService['calculateDraft']>[0]) {
    return this.customPackageService.calculateDraft(input);
  }

  async checkoutCustomPackage(packageId: string) {
    return this.customPackageService.checkoutCustomPackage(packageId);
  }

  async applyManualOverride(command: ManualOverrideCommand) {
    return this.manualOverrideManager.overrideAssignment(command);
  }

  generateMonthlyReport(month: string, orders: FairnessOrder[], cleaners: CleanerCandidate[], stats: CleanerMonthlyStats[]) {
    return this.reportingModule.generateMonthlyFairnessReport(month, orders, cleaners, stats);
  }

  async handleSchedulingRequest(request: SchedulingRequest) {
    const duration = this.durationEstimator.estimate(request.area);
    return {
      request,
      duration,
      nextAction: request.customPackageId ? 'CHECKOUT_CUSTOM_PACKAGE' : 'SHOW_CALENDAR',
    };
  }
}
