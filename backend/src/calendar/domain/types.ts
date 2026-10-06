export interface PackagePlan {
  id: string;
  name: string;
  cleaningCount: number;
  validFrom: string;
  validTo: string;
  allowSameDay: boolean;
}

export interface UserPackage {
  id: string;
  userId: string;
  packageId: string;
  apartmentId: string;
  totalCleanings: number;
  bookedCleanings: number;
  status: string;
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

export interface ScheduledCleaning {
  id: string;
  userPackageId: string;
  apartmentId: string;
  date: string;
  startTime: string;
  endTime: string;
  status: string;
}

export interface SelectedDateWithTime {
  date: string;
  startTime: string;
  endTime: string;
}
