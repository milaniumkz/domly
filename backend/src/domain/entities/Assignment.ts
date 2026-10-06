export interface Assignment {
  id: string;
  orderId: string;
  cleanerId: string;
  assignedAt: Date;
  fairnessScoreSnapshot: FairnessScoreSnapshot;
  manualOverride: boolean;
}

export interface FairnessScoreSnapshot {
  totalScore: number;
  monthlyAreaScore: number;
  monthlyHoursScore: number;
  monthlyApartmentsScore: number;
  dayLoadScore: number;
  dailyTargetScore: number;
  districtScore: number;
  skillScore: number;
  randomScore: number;
  fitsTimeWindow: boolean;
  fitsDailyLimit: boolean;
  reasons: string[];
}
