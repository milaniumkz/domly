import {cleaningDurationMinutes} from '../../modules/cleaningDuration';
import { DurationEstimate } from '../domain/types';

export class DurationEstimator {
  estimate(area: number): DurationEstimate {
    return {area,estimatedHours:cleaningDurationMinutes(area)/60,complexityFactor:1};
  }
}
