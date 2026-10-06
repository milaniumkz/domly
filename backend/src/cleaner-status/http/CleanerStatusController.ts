import { Request, Response } from 'express';
import { ok } from '../../common/api';
import { AddonPriorityAssignmentService } from '../services/AddonPriorityAssignmentService';
import { CleanerStatusService } from '../services/CleanerStatusService';
import { CleanerStatusRepository } from '../repositories/CleanerStatusRepository';

export class CleanerStatusController {
  constructor(
    private readonly repo: CleanerStatusRepository,
    private readonly statusService: CleanerStatusService,
    private readonly priorityService: AddonPriorityAssignmentService,
  ) {}

  getProfile = async (req: Request, res: Response): Promise<void> => {
    const cleaner = await this.repo.getCleanerProfile(String(req.params.id));
    ok(res, { cleaner, privileges: cleaner ? this.statusService.getCleanerPrivileges(cleaner.status) : null });
  };

  getStatusHistory = async (req: Request, res: Response): Promise<void> => {
    const history = await this.repo.getStatusHistory(String(req.params.id));
    ok(res, { history });
  };

  getProgressToNextStatus = async (req: Request, res: Response): Promise<void> => {
    const cleaner = await this.repo.getCleanerProfile(String(req.params.id));
    if (!cleaner) throw new Error('Cleaner not found');
    const configs = await this.repo.getStatusConfigs();
    const progress = this.statusService.getProgressToNextStatus(cleaner, configs);
    ok(res, { progress });
  };

  getMonthlyEarningsBreakdown = async (req: Request, res: Response): Promise<void> => {
    const month = typeof req.query.month === 'string' ? req.query.month : new Date().toISOString().slice(0, 7);
    const breakdown = await this.repo.getCleanerMonthlyEarningsBreakdown(String(req.params.id), month);
    ok(res, { month, breakdown });
  };

  assignHighValueOrders = async (req: Request, res: Response): Promise<void> => {
    ok(res, { date: String(req.body.date ?? ''), mode: 'HIGH_VALUE_ASSIGNMENT' });
  };
}
