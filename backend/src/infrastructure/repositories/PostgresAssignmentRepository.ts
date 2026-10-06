import { Queryable } from '../../domain/repositories/UnitOfWork';
import { v4 as uuidv4 } from 'uuid';
import { AssignmentRepository } from '../../domain/repositories/AssignmentRepository';
import { Assignment, FairnessScoreSnapshot } from '../../domain/entities/Assignment';
import { Database } from '../db/Database';

function mapAssignment(row: any): Assignment {
  return {
    id: row.id,
    orderId: row.order_id,
    cleanerId: row.cleaner_id,
    assignedAt: new Date(row.assigned_at),
    fairnessScoreSnapshot: row.fairness_score_snapshot,
    manualOverride: row.manual_override,
  };
}

export class PostgresAssignmentRepository implements AssignmentRepository {
  constructor(private readonly db: Database, private readonly client?: Queryable) {}

  private get executor() {
    return this.client ?? this.db;
  }

  async create(orderId: string, cleanerId: string, snapshot: FairnessScoreSnapshot, manualOverride = false): Promise<Assignment> {
    const id = uuidv4();
    const result = await this.executor.query<any>(
      `INSERT INTO assignments (id, order_id, cleaner_id, fairness_score_snapshot, manual_override)
       VALUES ($1, $2, $3, $4, $5)
       RETURNING *`,
      [id, orderId, cleanerId, JSON.stringify(snapshot), manualOverride]
    );
    return mapAssignment(result.rows[0]);
  }

  async upsert(orderId: string, cleanerId: string, snapshot: FairnessScoreSnapshot, manualOverride = false): Promise<Assignment> {
    const result = await this.executor.query<any>(
      `INSERT INTO assignments (id, order_id, cleaner_id, fairness_score_snapshot, manual_override)
       VALUES ($1, $2, $3, $4, $5)
       ON CONFLICT (order_id)
       DO UPDATE SET cleaner_id = EXCLUDED.cleaner_id,
                     fairness_score_snapshot = EXCLUDED.fairness_score_snapshot,
                     manual_override = EXCLUDED.manual_override,
                     assigned_at = NOW()
       RETURNING *`,
      [uuidv4(), orderId, cleanerId, JSON.stringify(snapshot), manualOverride]
    );
    return mapAssignment(result.rows[0]);
  }

  async getByOrderId(orderId: string): Promise<Assignment | null> {
    const result = await this.executor.query<any>('SELECT * FROM assignments WHERE order_id = $1', [orderId]);
    return result.rows[0] ? mapAssignment(result.rows[0]) : null;
  }

  async getByDate(date: string): Promise<Assignment[]> {
    const result = await this.executor.query<any>(
      `SELECT a.*
       FROM assignments a
       JOIN orders o ON o.id = a.order_id
       WHERE o.date = $1`,
      [date]
    );
    return result.rows.map(mapAssignment);
  }

  async deleteByOrderId(orderId: string): Promise<void> {
    await this.executor.query('DELETE FROM assignments WHERE order_id = $1', [orderId]);
  }

  async deleteRebalanceableByDate(date: string): Promise<void> {
    await this.executor.query(
      `DELETE FROM assignments a
       USING orders o
       WHERE a.order_id = o.id
         AND o.date = $1
         AND o.status = 'ASSIGNED'`,
      [date]
    );
  }
}
