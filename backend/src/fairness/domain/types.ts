export interface CleanerMonthlyStats {
  cleanerId: string;
  month: string;
  totalArea: number;
  totalHours: number;
  totalApartments: number;
  totalIncome: number;
  largeApartmentCount: number;
  smallApartmentCount: number;
}

export interface FairnessConfig {
  weightArea: number;
  weightHours: number;
  weightApartments: number;
  weightIncome: number;
  weightTravel: number;
  weightDayCapacity: number;
  weightSizePenalty: number;
  weightPriority: number;
  randomnessFactor: number;
  largeApartmentThreshold: number;
  targetDailyArea: number;
}

export interface CleanerCandidate {
  id: string;
  name: string;
  dailyWorkLimitHours: number;
  dayAssignedHours: number;
  dayAssignedArea: number;
  dayAssignedApartments: number;
  averageTravelCost?: number;
  cleanerPriorityPenaltyOrBonus?: number;
}

export interface FairnessOrder {
  id: string;
  month: string;
  area: number;
  estimatedHours: number;
  income: number;
  apartmentsCount: number;
  travelCostByCleaner?: Record<string, number>;
}

export interface MonthlyTargets {
  month: string;
  targetArea: number;
  targetHours: number;
  targetApartments: number;
  targetIncome: number;
}

export interface CleanerAssignmentScore {
  cleanerId: string;
  totalScore: number;
  fairnessCoefficient: number;
  weightedRandomScore: number;
  components: {
    deviationFromMonthlyTargetArea: number;
    deviationFromMonthlyTargetHours: number;
    deviationFromMonthlyTargetApartments: number;
    deviationFromMonthlyTargetIncome: number;
    currentDayRemainingCapacity: number;
    travelCost: number;
    cleanerPriorityPenaltyOrBonus: number;
    largeObjectPenalty: number;
  };
  explain: string[];
}

export interface MonthlyFairnessReport {
  month: string;
  targets: MonthlyTargets;
  cleaners: Array<{
    cleanerId: string;
    totalArea: number;
    totalHours: number;
    totalApartments: number;
    totalIncome: number;
    fairnessCoefficient: number;
    deviationArea: number;
    deviationHours: number;
    deviationApartments: number;
    deviationIncome: number;
    largeApartmentCount: number;
    smallApartmentCount: number;
  }>;
}
