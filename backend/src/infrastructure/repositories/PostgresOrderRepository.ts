import { Queryable } from '../../domain/repositories/UnitOfWork';
import { OrderRepository } from '../../domain/repositories/OrderRepository';
import { Order } from '../../domain/entities/Order';
import { Database } from '../db/Database';

function mapOrder(row: any): Order {
  return {
    id: row.id,
    apartmentId: row.apartment_id,
    date: row.date instanceof Date ? row.date.toISOString().slice(0, 10) : String(row.date),
    startTime: String(row.start_time).slice(0, 5),
    endTime: String(row.end_time).slice(0, 5),
    area: Number(row.area),
    estimatedDurationHours: Number(row.estimated_duration_hours),
    district: row.district,
    status: row.status,
    cleanerId: row.cleaner_id,
  };
}

export class PostgresOrderRepository implements OrderRepository {
  constructor(private readonly db: Database, private readonly client?: Queryable) {}

  private get executor() {
    return this.client ?? this.db;
  }

  async getById(orderId: string): Promise<Order | null> {
    const result = await this.executor.query<any>('SELECT * FROM orders WHERE id = $1', [orderId]);
    return result.rows[0] ? mapOrder(result.rows[0]) : null;
  }

  async getOrdersForDay(date: string): Promise<Order[]> {
    const result = await this.executor.query<any>('SELECT * FROM orders WHERE date = $1 ORDER BY start_time, area DESC', [date]);
    return result.rows.map(mapOrder);
  }

  async getUnassignedOrdersForDay(date: string): Promise<Order[]> {
    const result = await this.executor.query<any>(
      `SELECT * FROM orders
       WHERE date = $1
         AND status = 'PENDING'
         AND cleaner_id IS NULL
       ORDER BY estimated_duration_hours DESC, area DESC, start_time ASC`,
      [date]
    );
    return result.rows.map(mapOrder);
  }

  async setCleaner(orderId: string, cleanerId: string): Promise<void> {
    await this.executor.query(
      `UPDATE orders
       SET cleaner_id = $2,
           status = 'ASSIGNED',
           updated_at = NOW()
       WHERE id = $1`,
      [orderId, cleanerId]
    );
  }

  async clearCleaner(orderId: string): Promise<void> {
    await this.executor.query(
      `UPDATE orders
       SET cleaner_id = NULL,
           status = 'PENDING',
           updated_at = NOW()
       WHERE id = $1`,
      [orderId]
    );
  }

  async setStatus(orderId: string, status: string): Promise<void> {
    await this.executor.query('UPDATE orders SET status = $2, updated_at = NOW() WHERE id = $1', [orderId, status]);
  }
}
