import { Request, Response } from 'express';
import { ok } from '../../common/api';
import { CustomPackageService } from '../services/CustomPackageService';

export class CustomPackageController {
  constructor(private readonly service: CustomPackageService) {}

  getAddons = async (_req: Request, res: Response): Promise<void> => {
    const addons = await this.service.getAddons();
    ok(res, { addons });
  };

  createDraft = async (req: Request, res: Response): Promise<void> => {
    const draft = await this.service.createDraft(req.body);
    ok(res, { draft });
  };

  calculate = async (req: Request, res: Response): Promise<void> => {
    const payload = await this.service.calculateDraft(req.body);
    ok(res, payload);
  };

  confirm = async (req: Request, res: Response): Promise<void> => {
    const customPackage = await this.service.confirm(String(req.body.draftId));
    ok(res, { customPackage });
  };

  checkout = async (req: Request, res: Response): Promise<void> => {
    const customPackage = await this.service.checkoutCustomPackage(String(req.body.packageId));
    ok(res, { customPackage });
  };
}
