import {cleaningDurationMinutes} from '../../modules/cleaningDuration';
import { DurationEstimate } from '../domain/types';

export class DurationEstimator {
  estimate(area: number): DurationEstimate {
    const complexityFactor = area>=30 && area<75 ? 1
      : area>=75 && area<100 ? 1.05
      : area>=100 && area<150 ? 1.1
      : area>=150 && area<200 ? 1.15 : 1.25;
    return {area,estimatedHours:cleaningDurationMinutes(area)/60,complexityFactor};
  }
}
