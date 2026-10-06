import { Request, Response } from 'express';
import { ok } from '../../common/api';
import { SchedulingEngine } from '../services/SchedulingEngine';

export class SchedulingController {
  constructor(private readonly engine: SchedulingEngine) {}

  estimateDuration = async (req: Request, res: Response): Promise<void> => {
    const area = Number(req.query.area ?? 0);
    ok(res, { estimate: this.engine.estimateDuration(area) });
  };

  getCalendar = async (req: Request, res: Response): Promise<void> => {
    const calendar = await this.engine.getAvailabilityCalendar({
      apartmentId: String(req.query.apartmentId ?? ''),
      area: Number(req.query.area ?? 0),
      month: String(req.query.month ?? ''),
      packageId: typeof req.query.packageId === 'string' ? req.query.packageId : undefined,
      recurring: req.query.recurring === 'true',
    });
    ok(res, { calendar });
  };

  assignDay = async (req: Request, res: Response): Promise<void> => {
    const decisions = await this.engine.assignOrdersForDay(String(req.body.date ?? ''));
    ok(res, { decisions });
  };

  manualOverride = async (req: Request, res: Response): Promise<void> => {
    const result = await this.engine.applyManualOverride(req.body);
    ok(res, { result });
  };
}
