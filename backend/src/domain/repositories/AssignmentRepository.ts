import { Assignment, FairnessScoreSnapshot } from '../entities/Assignment';

export interface AssignmentRepository {
  create(orderId: string, cleanerId: string, snapshot: FairnessScoreSnapshot, manualOverride?: boolean): Promise<Assignment>;
  upsert(orderId: string, cleanerId: string, snapshot: FairnessScoreSnapshot, manualOverride?: boolean): Promise<Assignment>;
  getByOrderId(orderId: string): Promise<Assignment | null>;
  getByDate(date: string): Promise<Assignment[]>;
  deleteByOrderId(orderId: string): Promise<void>;
  deleteRebalanceableByDate(date: string): Promise<void>;
}
