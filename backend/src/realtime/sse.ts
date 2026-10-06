import { Router } from 'express';
import IORedis from 'ioredis';
import { auth } from '../common/auth';

const realtimeChannel = 'domly:realtime';
const clients = new Set<{ userId: string; write: (payload: string) => void }>();
let publisher: IORedis | null = null;
let subscriber: IORedis | null = null;

export function buildRealtimeRouter(): Router {
  const router = Router();
  router.get('/', auth([], { allowQueryToken: true }), (req, res) => {
    res.writeHead(200, {
      'Content-Type': 'text/event-stream',
      'Cache-Control': 'no-cache',
      Connection: 'keep-alive',
      'X-Accel-Buffering': 'no',
    });
    const client = {
      userId: req.user!.id,
      write: (payload: string) => res.write(`event: message\ndata: ${payload}\n\n`),
    };
    clients.add(client);
    client.write(JSON.stringify({ type: 'connected' }));
    const heartbeat = setInterval(() => {
      res.write(`event: ping\ndata: ${JSON.stringify({ time: new Date().toISOString() })}\n\n`);
    }, 25_000);
    req.on('close', () => {
      clearInterval(heartbeat);
      clients.delete(client);
    });
  });
  return router;
}

export function emitToUser(userId: string, event: unknown): void {
  const payload = JSON.stringify(event);
  for (const client of clients) {
    if (client.userId === userId) client.write(payload);
  }
}

export function configureRealtimeBus(redisUrl: string): void {
  if (publisher || subscriber) return;
  publisher = new IORedis(redisUrl, { maxRetriesPerRequest: null, lazyConnect: true });
  subscriber = new IORedis(redisUrl, { maxRetriesPerRequest: null });
  subscriber.subscribe(realtimeChannel).catch(() => undefined);
  subscriber.on('message', (_channel, message) => {
    try {
      const event = JSON.parse(message) as { userId?: string; payload?: unknown };
      if (!event.userId) return;
      emitToUser(event.userId, event.payload ?? {});
    } catch {
      // Ignore malformed realtime events; API response path must not fail because of SSE.
    }
  });
}

export async function publishToUser(userId: string, event: unknown): Promise<void> {
  if (!publisher) {
    emitToUser(userId, event);
    return;
  }
  try {
    await publisher.publish(realtimeChannel, JSON.stringify({ userId, payload: event }));
  } catch {
    emitToUser(userId, event);
  }
}

export async function closeRealtimeBus(): Promise<void> {
  await Promise.all([
    publisher?.quit().catch(() => undefined),
    subscriber?.quit().catch(() => undefined),
  ]);
  publisher = null;
  subscriber = null;
}
