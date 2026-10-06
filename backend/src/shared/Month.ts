export function monthKeyFromDate(date: string | Date): string {
  const value = date instanceof Date ? date : new Date(date);
  const month = String(value.getUTCMonth() + 1).padStart(2, '0');
  return `${value.getUTCFullYear()}-${month}`;
}

export function timeToMinutes(time: string): number {
  const [hours, minutes] = time.split(':').map(Number);
  return hours * 60 + minutes;
}

export function overlaps(aStart: string, aEnd: string, bStart: string, bEnd: string): boolean {
  const startA = timeToMinutes(aStart);
  const endA = timeToMinutes(aEnd);
  const startB = timeToMinutes(bStart);
  const endB = timeToMinutes(bEnd);
  return startA < endB && startB < endA;
}
