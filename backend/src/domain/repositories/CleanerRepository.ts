import { Cleaner, CleanerDayLoad, CleanerMonthlyStats } from '../entities/Cleaner';

export interface CleanerRepository {
  getActiveCleaners(): Promise<Cleaner[]>;
  getById(cleanerId: string): Promise<Cleaner | null>;
  getMonthlyStats(cleanerId: string, month: string): Promise<CleanerMonthlyStats>;
  getMonthlyStatsBulk(cleanerIds: string[], month: string): Promise<Map<string, CleanerMonthlyStats>>;
  getDayLoads(date: string): Promise<Map<string, CleanerDayLoad>>;
  applyAssignmentImpact(cleanerId: string, deltaArea: number, deltaHours: number, deltaApartments: number): Promise<void>;
}
