import { Addon, CustomPackageCalculation, CustomPackageDraft } from '../domain/types';

export class PricingEngine {
  calculateBaseCleaningPrice(area: number, cleaningType: string): number {
    const normalized = cleaningType.toLowerCase();
    const sqmRate =
      normalized.includes('генераль') ? 550 :
      normalized.includes('после ремонта') ? 700 :
      normalized.includes('премиум') ? 320 :
      normalized.includes('стандарт') ? 270 :
      220;
    return Math.round(area * sqmRate);
  }

  calculateRecurringAddonsPrice(addons: Addon[], area: number, cleaningCount: number): number {
    return addons.reduce((sum, addon) => sum + this.addonVisitPrice(addon, area) * cleaningCount, 0);
  }

  calculateOneTimeAddonsPrice(addons: Addon[], area: number): number {
    return addons.reduce((sum, addon) => sum + this.addonVisitPrice(addon, area), 0);
  }

  calculatePackageDiscount(cleaningCount: number, monthlyPrice: number): number {
    const rate =
      cleaningCount >= 8 ? 0.18 :
      cleaningCount >= 4 ? 0.12 :
      cleaningCount >= 2 ? 0.06 :
      0;
    return Math.round(monthlyPrice * rate);
  }

  buildCustomPackage(draft: CustomPackageDraft, recurringAddons: Addon[], oneTimeAddons: Addon[]): CustomPackageCalculation {
    const baseCleaningPrice = this.calculateBaseCleaningPrice(draft.area, draft.baseCleaningType);
    const recurringAddonsPrice = this.calculateRecurringAddonsPrice(recurringAddons, draft.area, draft.cleaningCount);
    const oneTimeAddonsPrice = this.calculateOneTimeAddonsPrice(oneTimeAddons, draft.area);
    const monthlyBeforeDiscount = (baseCleaningPrice * draft.cleaningCount) + recurringAddonsPrice + oneTimeAddonsPrice;
    const discount = this.calculatePackageDiscount(draft.cleaningCount, monthlyBeforeDiscount);
    const monthlyPrice = monthlyBeforeDiscount - discount;
    const oneVisitPrice = Math.round(monthlyPrice / Math.max(draft.cleaningCount, 1));
    const singles = (baseCleaningPrice + this.calculateRecurringAddonsPrice(recurringAddons, draft.area, 1)) * draft.cleaningCount + oneTimeAddonsPrice;
    const savingsComparedToSingles = Math.max(singles - monthlyPrice, 0);

    return {
      baseCleaningPrice,
      recurringAddonsPrice,
      oneTimeAddonsPrice,
      monthlyBeforeDiscount,
      discount,
      monthlyPrice,
      oneVisitPrice,
      savingsComparedToSingles,
    };
  }

  private addonVisitPrice(addon: Addon, area: number): number {
    if (addon.pricingType === 'PER_VISIT') return addon.price;
    if (addon.pricingType === 'PER_SQM') return Math.round(addon.price * area);
    return addon.price;
  }
}
