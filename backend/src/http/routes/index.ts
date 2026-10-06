import { Router } from 'express';
import { CalendarController } from '../../calendar/http/CalendarController';
import { asyncHandler } from '../../common/api';
import { CustomPackageController } from '../../custom-package/http/CustomPackageController';
import { CleanerController } from '../controllers/CleanerController';
import { ScheduleController } from '../controllers/ScheduleController';
import { SchedulerController } from '../controllers/SchedulerController';

export function buildRouter(
  schedulerController: SchedulerController,
  cleanerController: CleanerController,
  scheduleController: ScheduleController,
  calendarController: CalendarController,
  customPackageController: CustomPackageController,
): Router {
  const router = Router();

  router.post('/scheduler/assign-day', asyncHandler(schedulerController.assignDay));
  router.post('/scheduler/rebalance', asyncHandler(schedulerController.rebalance));
  router.post('/scheduler/reassign-cancelled', asyncHandler(schedulerController.reassignCancelled));
  router.get('/cleaners/:id/load', asyncHandler(cleanerController.getLoad));
  router.get('/schedule/day', asyncHandler(scheduleController.getDay));
  router.get('/packages/:id/calendar', asyncHandler(calendarController.getPackageCalendar));
  router.get('/calendar/available-dates', asyncHandler(calendarController.getAvailableDates));
  router.get('/calendar/available-slots', asyncHandler(calendarController.getAvailableSlots));
  router.post('/packages/:id/book-schedule', asyncHandler(calendarController.bookSchedule));
  router.post('/cleanings/:id/reschedule', asyncHandler(calendarController.rescheduleCleaning));
  router.get('/addons', asyncHandler(customPackageController.getAddons));
  router.post('/custom-package/draft', asyncHandler(customPackageController.createDraft));
  router.post('/custom-package/calculate', asyncHandler(customPackageController.calculate));
  router.post('/custom-package/confirm', asyncHandler(customPackageController.confirm));
  router.post('/custom-package/checkout', asyncHandler(customPackageController.checkout));

  return router;
}
