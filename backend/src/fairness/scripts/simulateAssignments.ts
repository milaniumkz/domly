import { FairnessEngine, DEFAULT_FAIRNESS_CONFIG } from '../services/FairnessEngine';
import { CleanerCandidate, CleanerMonthlyStats, FairnessOrder } from '../domain/types';

const cleaners: CleanerCandidate[] = [
  {
    id: 'c1',
    name: 'Asem',
    dailyWorkLimitHours: 8,
    dayAssignedHours: 0,
    dayAssignedArea: 0,
    dayAssignedApartments: 0,
    averageTravelCost: 0.08,
    cleanerPriorityPenaltyOrBonus: 0,
  },
  {
    id: 'c2',
    name: 'Dana',
    dailyWorkLimitHours: 8,
    dayAssignedHours: 0,
    dayAssignedArea: 0,
    dayAssignedApartments: 0,
    averageTravelCost: 0.04,
    cleanerPriorityPenaltyOrBonus: -0.01,
  },
  {
    id: 'c3',
    name: 'Mira',
    dailyWorkLimitHours: 8,
    dayAssignedHours: 0,
    dayAssignedArea: 0,
    dayAssignedApartments: 0,
    averageTravelCost: 0.06,
    cleanerPriorityPenaltyOrBonus: 0.01,
  },
];

const initialStats: CleanerMonthlyStats[] = [
  {
    cleanerId: 'c1',
    month: '2026-03',
    totalArea: 640,
    totalHours: 42,
    totalApartments: 12,
    totalIncome: 124000,
    largeApartmentCount: 5,
    smallApartmentCount: 7,
  },
  {
    cleanerId: 'c2',
    month: '2026-03',
    totalArea: 510,
    totalHours: 34,
    totalApartments: 10,
    totalIncome: 98000,
    largeApartmentCount: 3,
    smallApartmentCount: 7,
  },
  {
    cleanerId: 'c3',
    month: '2026-03',
    totalArea: 470,
    totalHours: 31,
    totalApartments: 11,
    totalIncome: 93000,
    largeApartmentCount: 2,
    smallApartmentCount: 9,
  },
];

const orders: FairnessOrder[] = [
  { id: 'o1', month: '2026-03', area: 45, estimatedHours: 2, income: 9000, apartmentsCount: 1, travelCostByCleaner: { c1: 0.06, c2: 0.03, c3: 0.05 } },
  { id: 'o2', month: '2026-03', area: 62, estimatedHours: 3, income: 12000, apartmentsCount: 1, travelCostByCleaner: { c1: 0.05, c2: 0.05, c3: 0.04 } },
  { id: 'o3', month: '2026-03', area: 118, estimatedHours: 5, income: 23000, apartmentsCount: 1, travelCostByCleaner: { c1: 0.02, c2: 0.07, c3: 0.08 } },
  { id: 'o4', month: '2026-03', area: 38, estimatedHours: 2, income: 8000, apartmentsCount: 1, travelCostByCleaner: { c1: 0.04, c2: 0.02, c3: 0.05 } },
  { id: 'o5', month: '2026-03', area: 155, estimatedHours: 6, income: 31000, apartmentsCount: 1, travelCostByCleaner: { c1: 0.09, c2: 0.06, c3: 0.05 } },
];

const engine = new FairnessEngine({
  ...DEFAULT_FAIRNESS_CONFIG,
  randomnessFactor: 0.05,
});

const result = engine.simulateAssignments('2026-03', orders, cleaners, initialStats);
console.log(JSON.stringify(result, null, 2));
