import { CleanerMonthlyStats } from '../../fairness/domain/types';
import { FairnessEngine } from '../../fairness/services/FairnessEngine';
import { CleanerCandidate, FairnessOrder, MonthlyFairnessReport } from '../../fairness/domain/types';

export class ReportingModule {
  constructor(private readonly fairnessEngine: FairnessEngine) {}

  generateMonthlyFairnessReport(
    month: string,
    orders: FairnessOrder[],
    cleaners: CleanerCandidate[],
    stats: CleanerMonthlyStats[],
  ): MonthlyFairnessReport {
    const targets = this.fairnessEngine.calculateMonthlyTargets(month, orders, cleaners);
    return this.fairnessEngine.generateMonthlyFairnessReport(month, stats, targets);
  }
}
