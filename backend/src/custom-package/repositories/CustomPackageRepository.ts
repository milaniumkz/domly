import { Addon, CustomPackage, CustomPackageDraft } from '../domain/types';

export interface CustomPackageRepository {
  getAddons(): Promise<Addon[]>;
  getAddonMap(ids: string[]): Promise<Map<string, Addon>>;
  getApartment(apartmentId: string): Promise<{ id: string; address: string; district: string; area: number } | null>;
  createDraft(input: Omit<CustomPackageDraft, 'id'>): Promise<CustomPackageDraft>;
  updateDraft(id: string, patch: Partial<CustomPackageDraft>): Promise<CustomPackageDraft>;
  getDraft(id: string): Promise<CustomPackageDraft | null>;
  createCustomPackage(input: Omit<CustomPackage, 'id'>): Promise<CustomPackage>;
  getCustomPackage(id: string): Promise<CustomPackage | null>;
  markCustomPackageCheckout(id: string): Promise<CustomPackage>;
}
