import { Queryable } from '../../domain/repositories/UnitOfWork';
import { CleanerRepository } from '../../domain/repositories/CleanerRepository';
import { Cleaner, CleanerDayLoad, CleanerMonthlyStats } from '../../domain/entities/Cleaner';
import { Database } from '../db/Database';

function mapCleaner(row: any): Cleaner {
  return {
    id: row.id,
    name: row.name,
    active: row.active,
    dailyWorkLimitHours: Number(row.daily_work_limit_hours),
    monthlyAssignedArea: Number(row.monthly_assigned_area),
    monthlyAssignedHours: Number(row.monthly_assigned_hours),
    monthlyAssignedApartments: Number(row.monthly_assigned_apartments),
    skillLevel: row.skill_level,
    preferredZones: row.preferred_zones ?? [],
  };
}

export class PostgresCleanerRepository implements CleanerRepository {
  constructor(private readonly db: Database, private readonly client?: Queryable) {}

  private get executor() {
    return this.client ?? this.db;
  }

  async getActiveCleaners(): Promise<Cleaner[]> {
    const result = await this.executor.query<any>(
      'SELECT * FROM cleaners WHERE active = TRUE ORDER BY id'
    );
    return result.rows.map(mapCleaner);
  }

  async getById(cleanerId: string): Promise<Cleaner | null> {
    const result = await this.executor.query<any>('SELECT * FROM cleaners WHERE id = $1', [cleanerId]);
    return result.rows[0] ? mapCleaner(result.rows[0]) : null;
  }

  async getMonthlyStats(cleanerId: string, _month: string): Promise<CleanerMonthlyStats> {
    const result = await this.executor.query<any>(
      'SELECT monthly_assigned_area, monthly_assigned_hours, monthly_assigned_apartments FROM cleaners WHERE id = $1',
      [cleanerId]
    );
    const row = result.rows[0] ?? {};
    return {
      cleanerId,
      month: _month,
      assignedArea: Number(row.monthly_assigned_area ?? 0),
      assignedHours: Number(row.monthly_assigned_hours ?? 0),
      assignedApartments: Number(row.monthly_assigned_apartments ?? 0),
    };
  }

  async getMonthlyStatsBulk(cleanerIds: string[], month: string): Promise<Map<string, CleanerMonthlyStats>> {
    if (cleanerIds.length === 0) return new Map();
    const result = await this.executor.query<any>(
      'SELECT id, monthly_assigned_area, monthly_assigned_hours, monthly_assigned_apartments FROM cleaners WHERE id = ANY($1)',
      [cleanerIds]
    );
    const map = new Map<string, CleanerMonthlyStats>();
    for (const row of result.rows) {
      map.set(row.id, {
        cleanerId: row.id,
        month,
        assignedArea: Number(row.monthly_assigned_area ?? 0),
        assignedHours: Number(row.monthly_assigned_hours ?? 0),
        assignedApartments: Number(row.monthly_assigned_apartments ?? 0),
      });
    }
    return map;
  }

  async getDayLoads(date: string): Promise<Map<string, CleanerDayLoad>> {
    const result = await this.executor.query<any>(
      `SELECT o.cleaner_id,
              COALESCE(SUM(o.area), 0) AS assigned_area,
              COALESCE(SUM(o.estimated_duration_hours), 0) AS assigned_hours,
              COUNT(*) AS assigned_apartments,
              JSON_AGG(JSON_BUILD_OBJECT('startTime', o.start_time, 'endTime', o.end_time)) AS intervals
       FROM orders o
       WHERE o.date = $1
         AND o.cleaner_id IS NOT NULL
         AND o.status IN ('ASSIGNED', 'IN_PROGRESS', 'COMPLETED')
       GROUP BY o.cleaner_id`,
      [date]
    );

    const map = new Map<string, CleanerDayLoad>();
    for (const row of result.rows) {
      map.set(row.cleaner_id, {
        cleanerId: row.cleaner_id,
        date,
        assignedArea: Number(row.assigned_area ?? 0),
        assignedHours: Number(row.assigned_hours ?? 0),
        assignedApartments: Number(row.assigned_apartments ?? 0),
        intervals: Array.isArray(row.intervals) ? row.intervals : [],
      });
    }
    return map;
  }

  async applyAssignmentImpact(cleanerId: string, deltaArea: number, deltaHours: number, deltaApartments: number): Promise<void> {
    await this.executor.query(
      `UPDATE cleaners
       SET monthly_assigned_area = monthly_assigned_area + $2,
           monthly_assigned_hours = monthly_assigned_hours + $3,
           monthly_assigned_apartments = monthly_assigned_apartments + $4,
           updated_at = NOW()
       WHERE id = $1`,
      [cleanerId, deltaArea, deltaHours, deltaApartments]
    );
  }
}
