export interface AvailableDate {
  date: string;
  availableSlots: number;
}

export interface CleaningSlot {
  id: string;
  date: string;
  startTime: string;
  endTime: string;
  availableCapacity: number;
  district: string;
  isClosed: boolean;
}

export interface SelectedDateWithTime {
  date: string;
  startTime: string;
  endTime: string;
}

export interface PackageCalendarResponse {
  ok: boolean;
  packageId: string;
  month: string;
  dates: AvailableDate[];
}
