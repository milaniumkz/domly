import { AssignmentRepository } from '../../domain/repositories/AssignmentRepository';
import { CleanerRepository } from '../../domain/repositories/CleanerRepository';
import { OrderRepository } from '../../domain/repositories/OrderRepository';
import { UnitOfWork } from '../../domain/repositories/UnitOfWork';
import { FairnessScoreSnapshot } from '../../domain/entities/Assignment';
import { ManualOverrideCommand } from '../domain/types';

export class ManualOverrideManager {
  constructor(
    private readonly orders: OrderRepository,
    private readonly assignments: AssignmentRepository,
    private readonly cleaners: CleanerRepository,
    private readonly uow: UnitOfWork,
  ) {}

  async overrideAssignment(command: ManualOverrideCommand) {
    return this.uow.transaction(async () => {
      const order = await this.orders.getById(command.orderId);
      if (!order) throw new Error('Order not found');
      const cleaner = await this.cleaners.getById(command.cleanerId);
      if (!cleaner || !cleaner.active) throw new Error('Cleaner not found or inactive');

      const existing = await this.assignments.getByOrderId(command.orderId);
      if (existing) {
        await this.cleaners.applyAssignmentImpact(existing.cleanerId, -order.area, -order.estimatedDurationHours, -1);
      }

      const snapshot: FairnessScoreSnapshot = {
        totalScore: 0,
        monthlyAreaScore: 0,
        monthlyHoursScore: 0,
        monthlyApartmentsScore: 0,
        dayLoadScore: 0,
        dailyTargetScore: 0,
        districtScore: 0,
        skillScore: 0,
        randomScore: 0,
        fitsTimeWindow: true,
        fitsDailyLimit: true,
        reasons: [`manual_override:${command.reason}`],
      };

      await this.orders.setCleaner(command.orderId, command.cleanerId);
      await this.assignments.upsert(command.orderId, command.cleanerId, snapshot, true);
      await this.cleaners.applyAssignmentImpact(command.cleanerId, order.area, order.estimatedDurationHours, 1);

      return {
        orderId: command.orderId,
        cleanerId: command.cleanerId,
        managerId: command.managerId,
        reason: command.reason,
      };
    });
  }
}
