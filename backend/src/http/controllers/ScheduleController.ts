import { Request, Response } from 'express';
import { ok } from '../../common/api';
import { OrderRepository } from '../../domain/repositories/OrderRepository';

export class ScheduleController {
  constructor(private readonly orders: OrderRepository) {}

  getDay = async (req: Request, res: Response): Promise<void> => {
    const date = String(req.query.date ?? '');
    const orders = await this.orders.getOrdersForDay(date);
    ok(res, { date, orders });
  };
}
