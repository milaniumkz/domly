import { Request, Response } from 'express';
import { ok } from '../../common/api';
import { SchedulerService } from '../../application/use-cases/SchedulerService';
import { monthKeyFromDate } from '../../shared/Month';

export class CleanerController {
  constructor(private readonly scheduler: SchedulerService) {}

  getLoad = async (req: Request, res: Response): Promise<void> => {
    const cleanerId = String(req.params.id);
    const month = typeof req.query.month === 'string' ? req.query.month : monthKeyFromDate(new Date());
    const stats = await this.scheduler.getCleanerMonthlyStats(cleanerId, month);
    ok(res, { stats });
  };

  getProgress = async (req: Request, res: Response): Promise<void> => {
    const cleanerId = String(req.params.id);
    const month = typeof req.query.month === 'string' ? req.query.month : monthKeyFromDate(new Date());
    const stats = await this.scheduler.getCleanerMonthlyStats(cleanerId, month);
    ok(res, { cleanerId, month, stats });
  };
}
