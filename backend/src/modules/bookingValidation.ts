import {ApiError} from '../common/api';

/** Service dates are local to Kazakhstan (UTC+5), independently of server TZ. */
export function validateBookingStart(date: unknown, time: unknown, now = Date.now()) {
  const day = String(date ?? '');
  const clock = String(time ?? '');
  if (!/^\d{4}-\d{2}-\d{2}$/.test(day) || !/^([01]\d|2[0-3]):[0-5]\d(?::[0-5]\d)?$/.test(clock)) {
    throw new ApiError(400, 'invalid_order_time', 'Выберите корректные дату и время уборки.');
  }
  const calendar = new Date(day + 'T00:00:00Z');
  if (!Number.isFinite(calendar.getTime()) || calendar.toISOString().slice(0, 10) !== day) {
    throw new ApiError(400, 'invalid_order_time', 'Выберите корректную дату уборки.');
  }
  const timestamp = Date.parse(day + 'T' + (clock.length === 5 ? clock + ':00' : clock) + '+05:00');
  if (!Number.isFinite(timestamp) || timestamp <= now) {
    throw new ApiError(400, 'past_order_time', 'Выберите будущие дату и время уборки.');
  }
}

/** Preserve the estimated duration; only the start is restricted to 08:00–18:00. */
export function fitsBookingHours(start: string, durationMinutes: number): boolean {
  if (!/^([01]\d|2[0-3]):[0-5]\d(?::00)?$/.test(start)) return false;
  const [hour, minute] = start.split(':').map(Number);
  const minutes = hour * 60 + minute;
  return Number.isFinite(durationMinutes) && durationMinutes > 0 &&
    minutes >= 8 * 60 && minutes <= 18 * 60;
}
export function validateBookingHours(start: string, durationMinutes: number) {
  if (!fitsBookingHours(start, durationMinutes)) {
    throw new ApiError(400, 'invalid_order_time', 'Начало уборки — с 08:00 до 18:00 включительно. Выберите другое время начала.');
  }
}
