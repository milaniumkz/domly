export class CapacityPlanner {
  canFitOrder(dayAssignedHours: number, dailyWorkLimitHours: number, orderHours: number): boolean {
    return dayAssignedHours + orderHours <= dailyWorkLimitHours;
  }

  remainingCapacity(dayAssignedHours: number, dailyWorkLimitHours: number): number {
    return Math.max(dailyWorkLimitHours - dayAssignedHours, 0);
  }
}
