import { Order } from '../entities/Order';

export interface OrderRepository {
  getById(orderId: string): Promise<Order | null>;
  getOrdersForDay(date: string): Promise<Order[]>;
  getUnassignedOrdersForDay(date: string): Promise<Order[]>;
  setCleaner(orderId: string, cleanerId: string): Promise<void>;
  clearCleaner(orderId: string): Promise<void>;
  setStatus(orderId: string, status: string): Promise<void>;
}
