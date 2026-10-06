import { DurationEstimate } from '../domain/types';

export class DurationEstimator {
  estimate(area: number): DurationEstimate {
    if (area >= 30 && area < 50) return { area, estimatedHours: 2, complexityFactor: 1 };
    if (area >= 50 && area < 75) return { area, estimatedHours: 3, complexityFactor: 1 };
    if (area >= 75 && area < 100) return { area, estimatedHours: 4, complexityFactor: 1.05 };
    if (area >= 100 && area < 150) return { area, estimatedHours: 5, complexityFactor: 1.1 };
    if (area >= 150 && area < 200) return { area, estimatedHours: 6, complexityFactor: 1.15 };
    return { area, estimatedHours: Math.max(7, Math.ceil(area / 35)), complexityFactor: 1.25 };
  }
}
