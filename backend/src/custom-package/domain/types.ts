export type AddonPricingType = 'FIXED' | 'PER_VISIT' | 'PER_SQM';

export interface Addon {
  id: string;
  name: string;
  pricingType: AddonPricingType;
  price: number;
  repeatable: boolean;
}

export interface CustomPackageDraft {
  id: string;
  userId: string;
  apartmentId: string;
  area: number;
  cleaningCount: number;
  baseCleaningType: string;
  recurringAddons: string[];
  oneTimeAddons: string[];
  preferredDays: string[];
  preferredTimeRanges: string[];
  estimatedMonthlyPrice: number;
  configJson: Record<string, unknown>;
}

export interface CustomPackage {
  id: string;
  userId: string;
  apartmentId: string;
  configJson: Record<string, unknown>;
  monthlyPrice: number;
  discount: number;
  status: string;
}

export interface CustomPackageCalculation {
  baseCleaningPrice: number;
  recurringAddonsPrice: number;
  oneTimeAddonsPrice: number;
  monthlyBeforeDiscount: number;
  discount: number;
  monthlyPrice: number;
  oneVisitPrice: number;
  savingsComparedToSingles: number;
}
