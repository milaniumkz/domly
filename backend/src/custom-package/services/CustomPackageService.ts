import { UnitOfWork } from '../../domain/repositories/UnitOfWork';
import { CustomPackageRepository } from '../repositories/CustomPackageRepository';
import { CustomPackageDraft } from '../domain/types';
import { PricingEngine } from './PricingEngine';

export class CustomPackageService {
  constructor(
    private readonly repo: CustomPackageRepository,
    private readonly pricing: PricingEngine,
    private readonly uow: UnitOfWork,
  ) {}

  getAddons() {
    return this.repo.getAddons();
  }

  async createDraft(input: Omit<CustomPackageDraft, 'id' | 'estimatedMonthlyPrice' | 'configJson'>) {
    const draft = await this.repo.createDraft({
      ...input,
      estimatedMonthlyPrice: 0,
      configJson: {},
    });
    const calculation = await this.calculate(draft);
    return this.repo.updateDraft(draft.id, {
      estimatedMonthlyPrice: calculation.monthlyPrice,
      configJson: { calculation },
    });
  }

  async calculateDraft(input: {
    draftId?: string;
    userId: string;
    apartmentId: string;
    area: number;
    cleaningCount: number;
    baseCleaningType: string;
    recurringAddons: string[];
    oneTimeAddons: string[];
    preferredDays: string[];
    preferredTimeRanges: string[];
  }) {
    const draft = input.draftId
      ? await this.repo.updateDraft(input.draftId, {
          apartmentId: input.apartmentId,
          area: input.area,
          cleaningCount: input.cleaningCount,
          baseCleaningType: input.baseCleaningType,
          recurringAddons: input.recurringAddons,
          oneTimeAddons: input.oneTimeAddons,
          preferredDays: input.preferredDays,
          preferredTimeRanges: input.preferredTimeRanges,
        })
      : await this.createDraft({
          userId: input.userId,
          apartmentId: input.apartmentId,
          area: input.area,
          cleaningCount: input.cleaningCount,
          baseCleaningType: input.baseCleaningType,
          recurringAddons: input.recurringAddons,
          oneTimeAddons: input.oneTimeAddons,
          preferredDays: input.preferredDays,
          preferredTimeRanges: input.preferredTimeRanges,
        });

    const calculation = await this.calculate(draft);
    const updated = await this.repo.updateDraft(draft.id, {
      estimatedMonthlyPrice: calculation.monthlyPrice,
      configJson: {
        area: draft.area,
        cleaningCount: draft.cleaningCount,
        baseCleaningType: draft.baseCleaningType,
        recurringAddons: draft.recurringAddons,
        oneTimeAddons: draft.oneTimeAddons,
        preferredDays: draft.preferredDays,
        preferredTimeRanges: draft.preferredTimeRanges,
        calculation,
      },
    });
    return { draft: updated, calculation };
  }

  async confirm(draftId: string) {
    const draft = await this.repo.getDraft(draftId);
    if (!draft) throw new Error('Draft not found');
    const calculation = await this.calculate(draft);
    return this.repo.createCustomPackage({
      userId: draft.userId,
      apartmentId: draft.apartmentId,
      configJson: {
        area: draft.area,
        cleaningCount: draft.cleaningCount,
        baseCleaningType: draft.baseCleaningType,
        recurringAddons: draft.recurringAddons,
        oneTimeAddons: draft.oneTimeAddons,
        preferredDays: draft.preferredDays,
        preferredTimeRanges: draft.preferredTimeRanges,
        calculation,
      },
      monthlyPrice: calculation.monthlyPrice,
      discount: calculation.discount,
      status: 'CONFIRMED',
    });
  }

  async checkoutCustomPackage(packageId: string) {
    return this.uow.transaction(async () => {
      return this.repo.markCustomPackageCheckout(packageId);
    });
  }

  private async calculate(draft: CustomPackageDraft) {
    const recurringMap = await this.repo.getAddonMap(draft.recurringAddons);
    const oneTimeMap = await this.repo.getAddonMap(draft.oneTimeAddons);
    return this.pricing.buildCustomPackage(
      draft,
      draft.recurringAddons.map((id) => recurringMap.get(id)).filter(Boolean) as any,
      draft.oneTimeAddons.map((id) => oneTimeMap.get(id)).filter(Boolean) as any,
    );
  }
}
