import { Queryable } from '../../domain/repositories/UnitOfWork';
import { v4 as uuidv4 } from 'uuid';
import { Database } from '../../infrastructure/db/Database';
import { CleaningSlot, PackagePlan, ScheduledCleaning, SelectedDateWithTime, UserPackage } from '../domain/types';
import { CalendarRepository } from './CalendarRepository';

function dateString(value: unknown): string {
  return value instanceof Date ? value.toISOString().slice(0, 10) : String(value);
}

function timeString(value: unknown): string {
  return String(value).slice(0, 5);
}

export class PostgresCalendarRepository implements CalendarRepository {
  constructor(private readonly db: Database, private readonly client?: Queryable) {}

  private get executor() {
    return this.client ?? this.db;
  }

  async getPackagePlan(packageId: string): Promise<PackagePlan | null> {
    const result = await this.executor.query<any>('SELECT * FROM package_plans WHERE id = $1', [packageId]);
    const row = result.rows[0];
    if (!row) return null;
    return {
      id: row.id,
      name: row.name,
      cleaningCount: row.cleaning_count,
      validFrom: dateString(row.valid_from),
      validTo: dateString(row.valid_to),
      allowSameDay: row.allow_same_day,
    };
  }

  async getUserPackage(userPackageId: string): Promise<UserPackage | null> {
    const result = await this.executor.query<any>('SELECT * FROM user_packages WHERE id = $1', [userPackageId]);
    const row = result.rows[0];
    if (!row) return null;
    return {
      id: row.id,
      userId: row.user_id,
      packageId: row.package_id,
      apartmentId: row.apartment_id,
      totalCleanings: row.total_cleanings,
      bookedCleanings: row.booked_cleanings,
      status: row.status,
    };
  }

  async getUserPackageByPackage(userId: string, apartmentId: string, packageId: string): Promise<UserPackage | null> {
    const result = await this.executor.query<any>(
      `SELECT * FROM user_packages
       WHERE user_id = $1 AND apartment_id = $2 AND package_id = $3 AND status = 'ACTIVE'
       ORDER BY created_at DESC LIMIT 1`,
      [userId, apartmentId, packageId]
    );
    const row = result.rows[0];
    if (!row) return null;
    return {
      id: row.id,
      userId: row.user_id,
      packageId: row.package_id,
      apartmentId: row.apartment_id,
      totalCleanings: row.total_cleanings,
      bookedCleanings: row.booked_cleanings,
      status: row.status,
    };
  }

  async getApartment(apartmentId: string): Promise<{ id: string; district: string; area: number } | null> {
    const result = await this.executor.query<any>('SELECT * FROM apartments WHERE id = $1', [apartmentId]);
    const row = result.rows[0];
    return row ? { id: row.id, district: row.district, area: Number(row.area) } : null;
  }

  async getClosedDays(monthStart: string, monthEnd: string): Promise<Set<string>> {
    const result = await this.executor.query<any>(
      'SELECT day FROM closed_days WHERE day BETWEEN $1 AND $2',
      [monthStart, monthEnd]
    );
    return new Set(result.rows.map((row) => dateString(row.day)));
  }

  async getCleaningSlots(date: string, district: string): Promise<CleaningSlot[]> {
    const result = await this.executor.query<any>(
      `SELECT * FROM cleaning_slots
       WHERE date = $1 AND district = $2
       ORDER BY start_time`,
      [date, district]
    );
    return result.rows.map((row) => ({
      id: row.id,
      date: dateString(row.date),
      startTime: timeString(row.start_time),
      endTime: timeString(row.end_time),
      availableCapacity: Number(row.available_capacity),
      district: row.district,
      isClosed: row.is_closed,
    }));
  }

  async getCleaningSlotsForMonth(monthStart: string, monthEnd: string, district: string): Promise<CleaningSlot[]> {
    const result = await this.executor.query<any>(
      `SELECT * FROM cleaning_slots
       WHERE date BETWEEN $1 AND $2 AND district = $3
       ORDER BY date, start_time`,
      [monthStart, monthEnd, district]
    );
    return result.rows.map((row) => ({
      id: row.id,
      date: dateString(row.date),
      startTime: timeString(row.start_time),
      endTime: timeString(row.end_time),
      availableCapacity: Number(row.available_capacity),
      district: row.district,
      isClosed: row.is_closed,
    }));
  }

  async getScheduledCleaningsByPackage(userPackageId: string): Promise<ScheduledCleaning[]> {
    const result = await this.executor.query<any>(
      'SELECT * FROM scheduled_cleanings WHERE user_package_id = $1 ORDER BY date, start_time',
      [userPackageId]
    );
    return result.rows.map((row) => ({
      id: row.id,
      userPackageId: row.user_package_id,
      apartmentId: row.apartment_id,
      date: dateString(row.date),
      startTime: timeString(row.start_time),
      endTime: timeString(row.end_time),
      status: row.status,
    }));
  }

  async getScheduledCleaning(cleaningId: string): Promise<ScheduledCleaning | null> {
    const result = await this.executor.query<any>('SELECT * FROM scheduled_cleanings WHERE id = $1', [cleaningId]);
    const row = result.rows[0];
    return row ? {
      id: row.id,
      userPackageId: row.user_package_id,
      apartmentId: row.apartment_id,
      date: dateString(row.date),
      startTime: timeString(row.start_time),
      endTime: timeString(row.end_time),
      status: row.status,
    } : null;
  }

  async createScheduledCleanings(userPackageId: string, apartmentId: string, selections: SelectedDateWithTime[]): Promise<ScheduledCleaning[]> {
    const created: ScheduledCleaning[] = [];
    for (const selection of selections) {
      const id = uuidv4();
      await this.executor.query(
        `INSERT INTO scheduled_cleanings (id, user_package_id, apartment_id, date, start_time, end_time, status)
         VALUES ($1, $2, $3, $4, $5, $6, 'BOOKED')`,
        [id, userPackageId, apartmentId, selection.date, selection.startTime, selection.endTime]
      );
      created.push({
        id,
        userPackageId,
        apartmentId,
        date: selection.date,
        startTime: selection.startTime,
        endTime: selection.endTime,
        status: 'BOOKED',
      });
    }
    return created;
  }

  async updateScheduledCleaning(cleaningId: string, selection: SelectedDateWithTime): Promise<ScheduledCleaning> {
    await this.executor.query(
      `UPDATE scheduled_cleanings
       SET date = $2, start_time = $3, end_time = $4, updated_at = NOW()
       WHERE id = $1`,
      [cleaningId, selection.date, selection.startTime, selection.endTime]
    );
    const updated = await this.getScheduledCleaning(cleaningId);
    if (!updated) throw new Error(`Cleaning ${cleaningId} not found after update`);
    return updated;
  }

  async decrementSlotCapacity(date: string, startTime: string, district: string): Promise<void> {
    const result = await this.executor.query<any>(
      `UPDATE cleaning_slots
       SET available_capacity = available_capacity - 1,
           updated_at = NOW()
       WHERE date = $1 AND start_time = $2 AND district = $3 AND available_capacity > 0 AND is_closed = FALSE
       RETURNING id`,
      [date, startTime, district]
    );
    if (result.rowCount !== 1) {
      throw new Error(`Slot unavailable for ${date} ${startTime} ${district}`);
    }
  }

  async incrementSlotCapacity(date: string, startTime: string, district: string): Promise<void> {
    await this.executor.query(
      `UPDATE cleaning_slots
       SET available_capacity = available_capacity + 1,
           updated_at = NOW()
       WHERE date = $1 AND start_time = $2 AND district = $3`,
      [date, startTime, district]
    );
  }

  async setUserPackageBookedCount(userPackageId: string, bookedCount: number): Promise<void> {
    await this.executor.query(
      'UPDATE user_packages SET booked_cleanings = $2, updated_at = NOW() WHERE id = $1',
      [userPackageId, bookedCount]
    );
  }
}
