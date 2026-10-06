import test from 'node:test';
import assert from 'node:assert/strict';
import { SchedulerService } from '../application/use-cases/SchedulerService';
import { AssignmentRepository } from '../domain/repositories/AssignmentRepository';
import { CleanerRepository } from '../domain/repositories/CleanerRepository';
import { OrderRepository } from '../domain/repositories/OrderRepository';
import { UnitOfWork } from '../domain/repositories/UnitOfWork';
import { CleanerSkillLevel } from '../domain/enums/CleanerSkillLevel';
import { OrderStatus } from '../domain/enums/OrderStatus';
import { ConsoleLogger } from '../infrastructure/logging/Logger';

class FakeUow implements UnitOfWork {
  async transaction<R>(work: (ctx: { query: () => Promise<{ rows: any[] }> }) => Promise<R>): Promise<R> {
    return work({ query: async () => ({ rows: [] }) });
  }
}

class FakeCleanerRepository implements CleanerRepository {
  constructor(public cleaners: any[], public dayLoads = new Map()) {}
  async getActiveCleaners() { return this.cleaners.filter((item) => item.active); }
  async getById(id: string) { return this.cleaners.find((item) => item.id === id) ?? null; }
  async getMonthlyStats(cleanerId: string, month: string) {
    const cleaner = this.cleaners.find((item) => item.id === cleanerId)!;
    return { cleanerId, month, assignedArea: cleaner.monthlyAssignedArea, assignedHours: cleaner.monthlyAssignedHours, assignedApartments: cleaner.monthlyAssignedApartments };
  }
  async getMonthlyStatsBulk(cleanerIds: string[], month: string) {
    const map = new Map();
    for (const cleanerId of cleanerIds) map.set(cleanerId, await this.getMonthlyStats(cleanerId, month));
    return map;
  }
  async getDayLoads() { return this.dayLoads; }
  async applyAssignmentImpact(cleanerId: string, deltaArea: number, deltaHours: number, deltaApartments: number) {
    const cleaner = this.cleaners.find((item) => item.id === cleanerId)!;
    cleaner.monthlyAssignedArea += deltaArea;
    cleaner.monthlyAssignedHours += deltaHours;
    cleaner.monthlyAssignedApartments += deltaApartments;
  }
}

class FakeOrderRepository implements OrderRepository {
  constructor(public orders: any[]) {}
  async getById(orderId: string) { return this.orders.find((item) => item.id === orderId) ?? null; }
  async getOrdersForDay(date: string) { return this.orders.filter((item) => item.date === date); }
  async getUnassignedOrdersForDay(date: string) { return this.orders.filter((item) => item.date === date && item.status === OrderStatus.PENDING && item.cleanerId == null); }
  async setCleaner(orderId: string, cleanerId: string) {
    const order = this.orders.find((item) => item.id === orderId)!;
    order.cleanerId = cleanerId;
    order.status = OrderStatus.ASSIGNED;
  }
  async clearCleaner(orderId: string) {
    const order = this.orders.find((item) => item.id === orderId)!;
    order.cleanerId = null;
    order.status = OrderStatus.PENDING;
  }
  async setStatus(orderId: string, status: string) {
    const order = this.orders.find((item) => item.id === orderId)!;
    order.status = status;
  }
}

class FakeAssignmentRepository implements AssignmentRepository {
  public items: any[] = [];
  async create(orderId: string, cleanerId: string, fairnessScoreSnapshot: any) {
    const assignment = { id: `${orderId}_${cleanerId}`, orderId, cleanerId, assignedAt: new Date(), fairnessScoreSnapshot, manualOverride: false };
    this.items.push(assignment);
    return assignment;
  }
  async upsert(orderId: string, cleanerId: string, fairnessScoreSnapshot: any) {
    const existing = this.items.find((item) => item.orderId === orderId);
    if (existing) {
      existing.cleanerId = cleanerId;
      existing.fairnessScoreSnapshot = fairnessScoreSnapshot;
      return existing;
    }
    return this.create(orderId, cleanerId, fairnessScoreSnapshot);
  }
  async getByOrderId(orderId: string) { return this.items.find((item) => item.orderId === orderId) ?? null; }
  async getByDate() { return this.items; }
  async deleteByOrderId(orderId: string) { this.items = this.items.filter((item) => item.orderId !== orderId); }
  async deleteRebalanceableByDate() { this.items = []; }
}

function createService(overrides: Partial<{ cleaners: any[]; orders: any[]; random: () => number }> = {}) {
  const cleanerRepository = new FakeCleanerRepository(overrides.cleaners ?? [
    {
      id: 'c1',
      name: 'A',
      active: true,
      dailyWorkLimitHours: 8,
      monthlyAssignedArea: 150,
      monthlyAssignedHours: 10,
      monthlyAssignedApartments: 3,
      skillLevel: CleanerSkillLevel.MIDDLE,
      preferredZones: ['center'],
    },
    {
      id: 'c2',
      name: 'B',
      active: true,
      dailyWorkLimitHours: 8,
      monthlyAssignedArea: 80,
      monthlyAssignedHours: 5,
      monthlyAssignedApartments: 2,
      skillLevel: CleanerSkillLevel.SENIOR,
      preferredZones: ['center'],
    },
  ]);
  const orderRepository = new FakeOrderRepository(overrides.orders ?? [
    {
      id: 'o1', apartmentId: 'a1', date: '2026-03-25', startTime: '10:00', endTime: '13:00', area: 60, estimatedDurationHours: 3, district: 'center', status: OrderStatus.PENDING, cleanerId: null,
    },
  ]);
  const assignments = new FakeAssignmentRepository();
  const service = new SchedulerService(cleanerRepository, orderRepository, assignments, new FakeUow(), new ConsoleLogger(), overrides.random ?? (() => 0));
  return { service, cleanerRepository, orderRepository, assignments };
}

test('estimateCleaningDuration uses area buckets', () => {
  const { service } = createService();
  assert.equal(service.estimateCleaningDuration(45), 2);
  assert.equal(service.estimateCleaningDuration(60), 3);
  assert.equal(service.estimateCleaningDuration(90), 4);
  assert.equal(service.estimateCleaningDuration(120), 5);
  assert.equal(service.estimateCleaningDuration(170), 6);
});

test('calculateCleanerFairnessScore prefers less loaded cleaner', async () => {
  const { service, cleanerRepository, orderRepository } = createService();
  const cleaners = await cleanerRepository.getActiveCleaners();
  const order = await orderRepository.getById('o1');
  const monthContext = { month: '2026-03', averageArea: 115, averageHours: 7.5, averageApartments: 2.5 };
  const scoreA = service.calculateCleanerFairnessScore(cleaners[0], order!, monthContext);
  const scoreB = service.calculateCleanerFairnessScore(cleaners[1], order!, monthContext);
  assert.ok(scoreB.totalScore < scoreA.totalScore);
});

test('assignOrdersForDay assigns pending order to fair cleaner', async () => {
  const { service, orderRepository, assignments } = createService();
  const result = await service.assignOrdersForDay('2026-03-25');
  assert.equal(result[0]?.cleanerId, 'c2');
  const order = await orderRepository.getById('o1');
  assert.equal(order?.cleanerId, 'c2');
  assert.equal(assignments.items.length, 1);
});

test('getEligibleCleaners excludes time conflicts', async () => {
  const { service, cleanerRepository } = createService();
  cleanerRepository.dayLoads.set('c2', {
    cleanerId: 'c2',
    date: '2026-03-25',
    assignedArea: 30,
    assignedHours: 2,
    assignedApartments: 1,
    intervals: [{ startTime: '10:30', endTime: '12:00' }],
  });
  const eligible = await service.getEligibleCleaners('o1');
  assert.equal(eligible.length, 1);
  assert.equal(eligible[0]?.cleaner.id, 'c1');
});
