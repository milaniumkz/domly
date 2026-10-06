import { UnitOfWork } from '../../domain/repositories/UnitOfWork';
import { timeToMinutes } from '../../shared/Month';
import { CalendarRepository } from '../repositories/CalendarRepository';
import { CleaningSlot, SelectedDateWithTime } from '../domain/types';

function toMonthRange(month: string): { start: string; end: string } {
  const [year, monthIndex] = month.split('-').map(Number);
  const start = new Date(Date.UTC(year, monthIndex - 1, 1));
  const end = new Date(Date.UTC(year, monthIndex, 0));
  return {
    start: start.toISOString().slice(0, 10),
    end: end.toISOString().slice(0, 10),
  };
}

export class CalendarBookingService {
  constructor(
    private readonly repo: CalendarRepository,
    private readonly uow: UnitOfWork,
  ) {}

  estimateCleaningDuration(area: number): number {
    if (area >= 30 && area < 50) return 2;
    if (area >= 50 && area < 75) return 3;
    if (area >= 75 && area < 100) return 4;
    if (area >= 100 && area < 150) return 5;
    if (area >= 150 && area < 200) return 6;
    if (area >= 200) return Math.max(7, Math.ceil(area / 35));
    return 1.5;
  }

  async getAvailableDates(userId: string, apartmentId: string, packageId: string, month: string): Promise<Array<{ date: string; availableSlots: number }>> {
    const userPackage = await this.repo.getUserPackageByPackage(userId, apartmentId, packageId);
    if (!userPackage) throw new Error('Active package not found');
    const apartment = await this.repo.getApartment(apartmentId);
    if (!apartment) throw new Error('Apartment not found');
    const { start, end } = toMonthRange(month);
    const closedDays = await this.repo.getClosedDays(start, end);
    const slots = await this.repo.getCleaningSlotsForMonth(start, end, apartment.district);

    const grouped = new Map<string, number>();
    for (const slot of slots) {
      if (slot.isClosed || slot.availableCapacity <= 0 || closedDays.has(slot.date)) continue;
      grouped.set(slot.date, (grouped.get(slot.date) ?? 0) + 1);
    }

    return Array.from(grouped.entries())
      .map(([date, availableSlots]) => ({ date, availableSlots }))
      .sort((a, b) => a.date.localeCompare(b.date));
  }

  async getAvailableTimeSlots(date: string, apartmentId: string): Promise<CleaningSlot[]> {
    const apartment = await this.repo.getApartment(apartmentId);
    if (!apartment) throw new Error('Apartment not found');
    const durationHours = this.estimateCleaningDuration(apartment.area);
    const slots = await this.repo.getCleaningSlots(date, apartment.district);

    return slots.filter((slot) => {
      if (slot.isClosed || slot.availableCapacity <= 0) return false;
      const duration = (timeToMinutes(slot.endTime) - timeToMinutes(slot.startTime)) / 60;
      return duration >= durationHours;
    });
  }

  validatePackageBookingSelection(selectedDates: SelectedDateWithTime[], packageRules: { cleaningCount: number; allowSameDay: boolean }): void {
    if (selectedDates.length !== packageRules.cleaningCount) {
      throw new Error(`Expected exactly ${packageRules.cleaningCount} selections`);
    }

    const seenDates = new Set<string>();
    for (const selection of selectedDates) {
      if (!packageRules.allowSameDay && seenDates.has(selection.date)) {
        throw new Error(`Duplicate date is not allowed: ${selection.date}`);
      }
      seenDates.add(selection.date);
    }
  }

  async bookPackageSchedule(userPackageId: string, selectedDatesWithTime: SelectedDateWithTime[]) {
    const userPackage = await this.repo.getUserPackage(userPackageId);
    if (!userPackage) throw new Error('User package not found');
    const packagePlan = await this.repo.getPackagePlan(userPackage.packageId);
    if (!packagePlan) throw new Error('Package plan not found');
    const apartment = await this.repo.getApartment(userPackage.apartmentId);
    if (!apartment) throw new Error('Apartment not found');

    this.validatePackageBookingSelection(selectedDatesWithTime, {
      cleaningCount: userPackage.totalCleanings,
      allowSameDay: packagePlan.allowSameDay,
    });

    await this.uow.transaction(async () => {
      for (const selection of selectedDatesWithTime) {
        const available = await this.getAvailableTimeSlots(selection.date, userPackage.apartmentId);
        const match = available.find((slot) => slot.startTime === selection.startTime && slot.endTime === selection.endTime);
        if (!match) {
          throw new Error(`Slot unavailable for ${selection.date} ${selection.startTime}`);
        }
        await this.repo.decrementSlotCapacity(selection.date, selection.startTime, apartment.district);
      }

      await this.repo.createScheduledCleanings(userPackageId, userPackage.apartmentId, selectedDatesWithTime);
      await this.repo.setUserPackageBookedCount(userPackageId, selectedDatesWithTime.length);
    });

    return this.repo.getScheduledCleaningsByPackage(userPackageId);
  }

  async suggestOptimalDates(userPackageId: string): Promise<SelectedDateWithTime[]> {
    const userPackage = await this.repo.getUserPackage(userPackageId);
    if (!userPackage) throw new Error('User package not found');
    const packagePlan = await this.repo.getPackagePlan(userPackage.packageId);
    if (!packagePlan) throw new Error('Package plan not found');
    const apartment = await this.repo.getApartment(userPackage.apartmentId);
    if (!apartment) throw new Error('Apartment not found');

    const month = userPackage.status === 'ACTIVE' ? packagePlan.validFrom.slice(0, 7) : new Date().toISOString().slice(0, 7);
    const dates = await this.getAvailableDates(userPackage.userId, userPackage.apartmentId, userPackage.packageId, month);
    const step = Math.max(Math.floor(dates.length / Math.max(packagePlan.cleaningCount, 1)), 1);

    const suggestions: SelectedDateWithTime[] = [];
    for (let i = 0; i < dates.length && suggestions.length < packagePlan.cleaningCount; i += step) {
      const slots = await this.getAvailableTimeSlots(dates[i].date, apartment.id);
      if (slots.length === 0) continue;
      suggestions.push({
        date: dates[i].date,
        startTime: slots[0].startTime,
        endTime: slots[0].endTime,
      });
    }
    return suggestions;
  }

  async rescheduleCleaning(cleaningId: string, newDate: string, newTime: { startTime: string; endTime: string }) {
    const cleaning = await this.repo.getScheduledCleaning(cleaningId);
    if (!cleaning) throw new Error('Cleaning not found');
    const userPackage = await this.repo.getUserPackage(cleaning.userPackageId);
    if (!userPackage) throw new Error('User package not found');
    const apartment = await this.repo.getApartment(cleaning.apartmentId);
    if (!apartment) throw new Error('Apartment not found');

    const available = await this.getAvailableTimeSlots(newDate, cleaning.apartmentId);
    const match = available.find((slot) => slot.startTime === newTime.startTime && slot.endTime === newTime.endTime);
    if (!match) {
      throw new Error('Requested new slot is unavailable');
    }

    return this.uow.transaction(async () => {
      await this.repo.incrementSlotCapacity(cleaning.date, cleaning.startTime, apartment.district);
      await this.repo.decrementSlotCapacity(newDate, newTime.startTime, apartment.district);
      return this.repo.updateScheduledCleaning(cleaningId, {
        date: newDate,
        startTime: newTime.startTime,
        endTime: newTime.endTime,
      });
    });
  }
}
