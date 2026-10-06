export interface SchedulingRequest {
  userId: string;
  apartmentId: string;
  packageType: string;
  area: number;
  preferredDate?: string;
  preferredTimeRange?: string;
  recurring?: boolean;
  customPackageId?: string;
}

export interface DurationEstimate {
  area: number;
  estimatedHours: number;
  complexityFactor: number;
}

export interface AvailabilityQuery {
  apartmentId: string;
  area: number;
  month: string;
  packageId?: string;
  recurring?: boolean;
}

export interface AvailableCalendarDay {
  date: string;
  availableSlots: Array<{
    startTime: string;
    endTime: string;
    capacity: number;
  }>;
}

export interface AssignmentDecision {
  orderId: string;
  cleanerId: string | null;
  totalScore: number | null;
  explain: string[];
  assignedAt: string;
  mode: 'AUTO' | 'MANUAL';
}

export interface ManualOverrideCommand {
  orderId: string;
  cleanerId: string;
  managerId: string;
  reason: string;
}

export interface SchedulingAuditLog {
  id: string;
  entityType: 'ORDER' | 'PACKAGE' | 'ASSIGNMENT' | 'OVERRIDE';
  entityId: string;
  action: string;
  payload: Record<string, unknown>;
  createdAt: string;
  actorId?: string;
}
