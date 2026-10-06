import { CleaningSlot, PackageCalendarResponse, SelectedDateWithTime } from '../types/calendar';

const API_BASE = process.env.REACT_APP_API_BASE ?? 'http://localhost:8080';

export async function getPackageCalendar(packageId: string, userId: string, apartmentId: string, month: string): Promise<PackageCalendarResponse> {
  const params = new URLSearchParams({ userId, apartmentId, month });
  const response = await fetch(`${API_BASE}/packages/${packageId}/calendar?${params.toString()}`);
  if (!response.ok) throw new Error('Failed to load package calendar');
  return response.json();
}

export async function getAvailableTimeSlots(date: string, apartmentId: string): Promise<CleaningSlot[]> {
  const params = new URLSearchParams({ date, apartmentId });
  const response = await fetch(`${API_BASE}/calendar/available-slots?${params.toString()}`);
  if (!response.ok) throw new Error('Failed to load available slots');
  const payload = await response.json();
  return payload.slots;
}

export async function bookPackageSchedule(packageId: string, userPackageId: string, selectedDatesWithTime: SelectedDateWithTime[]) {
  const response = await fetch(`${API_BASE}/packages/${packageId}/book-schedule`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ userPackageId, selectedDatesWithTime }),
  });
  if (!response.ok) throw new Error('Failed to book schedule');
  return response.json();
}

export async function rescheduleCleaning(cleaningId: string, newDate: string, startTime: string, endTime: string) {
  const response = await fetch(`${API_BASE}/cleanings/${cleaningId}/reschedule`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ newDate, startTime, endTime }),
  });
  if (!response.ok) throw new Error('Failed to reschedule cleaning');
  return response.json();
}
