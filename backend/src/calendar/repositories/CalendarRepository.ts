import { CleaningSlot, PackagePlan, ScheduledCleaning, SelectedDateWithTime, UserPackage } from '../domain/types';

export interface CalendarRepository {
  getPackagePlan(packageId: string): Promise<PackagePlan | null>;
  getUserPackage(userPackageId: string): Promise<UserPackage | null>;
  getUserPackageByPackage(userId: string, apartmentId: string, packageId: string): Promise<UserPackage | null>;
  getApartment(apartmentId: string): Promise<{ id: string; district: string; area: number } | null>;
  getClosedDays(monthStart: string, monthEnd: string): Promise<Set<string>>;
  getCleaningSlots(date: string, district: string): Promise<CleaningSlot[]>;
  getCleaningSlotsForMonth(monthStart: string, monthEnd: string, district: string): Promise<CleaningSlot[]>;
  getScheduledCleaningsByPackage(userPackageId: string): Promise<ScheduledCleaning[]>;
  getScheduledCleaning(cleaningId: string): Promise<ScheduledCleaning | null>;
  createScheduledCleanings(userPackageId: string, apartmentId: string, selections: SelectedDateWithTime[]): Promise<ScheduledCleaning[]>;
  updateScheduledCleaning(cleaningId: string, selection: SelectedDateWithTime): Promise<ScheduledCleaning>;
  decrementSlotCapacity(date: string, startTime: string, district: string): Promise<void>;
  incrementSlotCapacity(date: string, startTime: string, district: string): Promise<void>;
  setUserPackageBookedCount(userPackageId: string, bookedCount: number): Promise<void>;
}
