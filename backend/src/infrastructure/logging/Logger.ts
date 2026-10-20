import {sanitize,safeText} from '../../technical/core';
export interface Logger {
  info(message: string, meta?: Record<string, unknown>): void;
  warn(message: string, meta?: Record<string, unknown>): void;
  error(message: string, meta?: Record<string, unknown>): void;
}

export class ConsoleLogger implements Logger {
  info(message: string, meta: Record<string, unknown> = {}): void {
    console.info(JSON.stringify({ level: 'info', message:safeText(message), ...sanitize(meta) }));
  }

  warn(message: string, meta: Record<string, unknown> = {}): void {
    console.warn(JSON.stringify({ level: 'warn', message:safeText(message), ...sanitize(meta) }));
  }

  error(message: string, meta: Record<string, unknown> = {}): void {
    console.error(JSON.stringify({ level: 'error', message:safeText(message), ...sanitize(meta) }));
  }
}
