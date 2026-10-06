import { OrderStatus } from '../enums/OrderStatus';

export interface Order {
  id: string;
  apartmentId: string;
  date: string;
  startTime: string;
  endTime: string;
  area: number;
  estimatedDurationHours: number;
  district: string;
  status: OrderStatus;
  cleanerId: string | null;
}
