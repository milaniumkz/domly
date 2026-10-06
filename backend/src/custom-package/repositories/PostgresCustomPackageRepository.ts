import { Queryable } from '../../domain/repositories/UnitOfWork';
import { v4 as uuidv4 } from 'uuid';
import { Database } from '../../infrastructure/db/Database';
import { Addon, CustomPackage, CustomPackageDraft } from '../domain/types';
import { CustomPackageRepository } from './CustomPackageRepository';

function mapAddon(row: any): Addon {
  return {
    id: row.id,
    name: row.name,
    pricingType: row.pricing_type,
    price: Number(row.price),
    repeatable: row.repeatable,
  };
}

function mapDraft(row: any): CustomPackageDraft {
  return {
    id: row.id,
    userId: row.user_id,
    apartmentId: row.apartment_id,
    area: Number(row.area),
    cleaningCount: row.cleaning_count,
    baseCleaningType: row.base_cleaning_type,
    recurringAddons: row.recurring_addons ?? [],
    oneTimeAddons: row.one_time_addons ?? [],
    preferredDays: row.preferred_days ?? [],
    preferredTimeRanges: row.preferred_time_ranges ?? [],
    estimatedMonthlyPrice: Number(row.estimated_monthly_price),
    configJson: row.config_json ?? {},
  };
}

function mapPackage(row: any): CustomPackage {
  return {
    id: row.id,
    userId: row.user_id,
    apartmentId: row.apartment_id,
    configJson: row.config_json ?? {},
    monthlyPrice: Number(row.monthly_price),
    discount: Number(row.discount),
    status: row.status,
  };
}

export class PostgresCustomPackageRepository implements CustomPackageRepository {
  constructor(private readonly db: Database, private readonly client?: Queryable) {}

  private get executor() {
    return this.client ?? this.db;
  }

  async getAddons(): Promise<Addon[]> {
    const result = await this.executor.query<any>('SELECT * FROM addons ORDER BY name');
    return result.rows.map(mapAddon);
  }

  async getAddonMap(ids: string[]): Promise<Map<string, Addon>> {
    if (ids.length === 0) return new Map();
    const result = await this.executor.query<any>('SELECT * FROM addons WHERE id = ANY($1)', [ids]);
    return new Map(result.rows.map((row) => [row.id, mapAddon(row)]));
  }

  async getApartment(apartmentId: string): Promise<{ id: string; address: string; district: string; area: number } | null> {
    const result = await this.executor.query<any>('SELECT * FROM apartments WHERE id = $1', [apartmentId]);
    const row = result.rows[0];
    return row ? { id: row.id, address: row.address, district: row.district, area: Number(row.area) } : null;
  }

  async createDraft(input: Omit<CustomPackageDraft, 'id'>): Promise<CustomPackageDraft> {
    const id = uuidv4();
    await this.executor.query(
      `INSERT INTO custom_package_drafts (
        id, user_id, apartment_id, area, cleaning_count, base_cleaning_type,
        recurring_addons, one_time_addons, preferred_days, preferred_time_ranges,
        estimated_monthly_price, config_json
      ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)`,
      [
        id,
        input.userId,
        input.apartmentId,
        input.area,
        input.cleaningCount,
        input.baseCleaningType,
        input.recurringAddons,
        input.oneTimeAddons,
        input.preferredDays,
        input.preferredTimeRanges,
        input.estimatedMonthlyPrice,
        JSON.stringify(input.configJson),
      ],
    );
    const created = await this.getDraft(id);
    if (!created) throw new Error('Draft not created');
    return created;
  }

  async updateDraft(id: string, patch: Partial<CustomPackageDraft>): Promise<CustomPackageDraft> {
    const current = await this.getDraft(id);
    if (!current) throw new Error('Draft not found');
    const next = { ...current, ...patch };
    await this.executor.query(
      `UPDATE custom_package_drafts
       SET apartment_id = $2,
           area = $3,
           cleaning_count = $4,
           base_cleaning_type = $5,
           recurring_addons = $6,
           one_time_addons = $7,
           preferred_days = $8,
           preferred_time_ranges = $9,
           estimated_monthly_price = $10,
           config_json = $11,
           updated_at = NOW()
       WHERE id = $1`,
      [
        id,
        next.apartmentId,
        next.area,
        next.cleaningCount,
        next.baseCleaningType,
        next.recurringAddons,
        next.oneTimeAddons,
        next.preferredDays,
        next.preferredTimeRanges,
        next.estimatedMonthlyPrice,
        JSON.stringify(next.configJson),
      ],
    );
    return (await this.getDraft(id))!;
  }

  async getDraft(id: string): Promise<CustomPackageDraft | null> {
    const result = await this.executor.query<any>('SELECT * FROM custom_package_drafts WHERE id = $1', [id]);
    return result.rows[0] ? mapDraft(result.rows[0]) : null;
  }

  async createCustomPackage(input: Omit<CustomPackage, 'id'>): Promise<CustomPackage> {
    const id = uuidv4();
    await this.executor.query(
      `INSERT INTO custom_packages (id, user_id, apartment_id, config_json, monthly_price, discount, status)
       VALUES ($1,$2,$3,$4,$5,$6,$7)`,
      [id, input.userId, input.apartmentId, JSON.stringify(input.configJson), input.monthlyPrice, input.discount, input.status],
    );
    return (await this.getCustomPackage(id))!;
  }

  async getCustomPackage(id: string): Promise<CustomPackage | null> {
    const result = await this.executor.query<any>('SELECT * FROM custom_packages WHERE id = $1', [id]);
    return result.rows[0] ? mapPackage(result.rows[0]) : null;
  }

  async markCustomPackageCheckout(id: string): Promise<CustomPackage> {
    await this.executor.query('UPDATE custom_packages SET status = $2, updated_at = NOW() WHERE id = $1', [id, 'PENDING_PAYMENT']);
    return (await this.getCustomPackage(id))!;
  }
}
