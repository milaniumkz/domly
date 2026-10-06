import { CleanerSkillLevel } from '../enums/CleanerSkillLevel';

export interface Cleaner {
  id: string;
  name: string;
  active: boolean;
  dailyWorkLimitHours: number;
  monthlyAssignedArea: number;
  monthlyAssignedHours: number;
  monthlyAssignedApartments: number;
  skillLevel: CleanerSkillLevel;
  preferredZones: string[];
}

export interface CleanerMonthlyStats {
  cleanerId: string;
  month: string;
  assignedArea: number;
  assignedHours: number;
  assignedApartments: number;
}

export interface CleanerDayLoad {
  cleanerId: string;
  date: string;
  assignedArea: number;
  assignedHours: number;
  assignedApartments: number;
  intervals: Array<{ startTime: string; endTime: string }>;
}
