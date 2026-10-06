import { Request, Response } from 'express';
import { ok } from '../../common/api';
import { SchedulerService } from '../../application/use-cases/SchedulerService';

export class SchedulerController {
  constructor(private readonly scheduler: SchedulerService) {}

  assignDay = async (req: Request, res: Response): Promise<void> => {
    const date = String(req.body.date ?? '');
    const result = await this.scheduler.assignOrdersForDay(date);
    ok(res, { date, assignments: result });
  };

  rebalance = async (req: Request, res: Response): Promise<void> => {
    const date = String(req.body.date ?? '');
    const result = await this.scheduler.rebalanceAssignments(date);
    ok(res, { date, assignments: result });
  };

  reassignCancelled = async (req: Request, res: Response): Promise<void> => {
    const orderId = String(req.body.orderId ?? '');
    const result = await this.scheduler.reassignCancelledOrder(orderId);
    ok(res, { orderId, assignments: result });
  };
}
