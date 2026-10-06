import {
  AssignmentConfig,
  CleanerMonthlyStats,
  CleanerProfile,
  CleanerStatusHistoryEntry,
  OrderAddonPriorityContext,
  StatusConfig,
} from '../domain/types';

export interface CleanerStatusRepository {
  getCleanerProfile(cleanerId: string): Promise<CleanerProfile | null>;
  getAllCleanerProfiles(): Promise<CleanerProfile[]>;
  getStatusConfigs(): Promise<StatusConfig[]>;
  getAssignmentConfig(): Promise<AssignmentConfig>;
  updateCleanerStatus(cleanerId: string, status: CleanerProfile['status']): Promise<void>;
  createStatusHistory(entry: Omit<CleanerStatusHistoryEntry, 'id' | 'createdAt'>): Promise<void>;
  getStatusHistory(cleanerId: string): Promise<CleanerStatusHistoryEntry[]>;
  getMonthlyStats(cleanerId: string, month: string): Promise<CleanerMonthlyStats>;
  getMonthlyStatsBulk(cleanerIds: string[], month: string): Promise<Map<string, CleanerMonthlyStats>>;
  getCleanerMonthlyEarningsBreakdown(cleanerId: string, month: string): Promise<{ totalIncome: number; addonIncome: number; bonuses: number }>;
  getOrder(orderId: string): Promise<OrderAddonPriorityContext | null>;
}
