import { Request, Response } from 'express';
import { ok } from '../../common/api';
import { CalendarBookingService } from '../services/CalendarBookingService';

export class CalendarController {
  constructor(private readonly service: CalendarBookingService) {}

  getPackageCalendar = async (req: Request, res: Response): Promise<void> => {
    const packageId = String(req.params.id);
    const apartmentId = String(req.query.apartmentId ?? '');
    const userId = String(req.query.userId ?? '');
    const month = String(req.query.month ?? new Date().toISOString().slice(0, 7));
    const dates = await this.service.getAvailableDates(userId, apartmentId, packageId, month);
    ok(res, { packageId, month, dates });
  };

  getAvailableDates = async (req: Request, res: Response): Promise<void> => {
    const userId = String(req.query.userId ?? '');
    const apartmentId = String(req.query.apartmentId ?? '');
    const packageId = String(req.query.packageId ?? '');
    const month = String(req.query.month ?? new Date().toISOString().slice(0, 7));
    const dates = await this.service.getAvailableDates(userId, apartmentId, packageId, month);
    ok(res, { dates });
  };

  getAvailableSlots = async (req: Request, res: Response): Promise<void> => {
    const date = String(req.query.date ?? '');
    const apartmentId = String(req.query.apartmentId ?? '');
    const slots = await this.service.getAvailableTimeSlots(date, apartmentId);
    ok(res, { slots });
  };

  bookSchedule = async (req: Request, res: Response): Promise<void> => {
    const userPackageId = String(req.body.userPackageId ?? '');
    const selectedDatesWithTime = Array.isArray(req.body.selectedDatesWithTime) ? req.body.selectedDatesWithTime : [];
    const schedule = await this.service.bookPackageSchedule(userPackageId, selectedDatesWithTime);
    ok(res, { schedule });
  };

  rescheduleCleaning = async (req: Request, res: Response): Promise<void> => {
    const cleaningId = String(req.params.id);
    const newDate = String(req.body.newDate ?? '');
    const newTime = {
      startTime: String(req.body.startTime ?? ''),
      endTime: String(req.body.endTime ?? ''),
    };
    const cleaning = await this.service.rescheduleCleaning(cleaningId, newDate, newTime);
    ok(res, { cleaning });
  };
}
