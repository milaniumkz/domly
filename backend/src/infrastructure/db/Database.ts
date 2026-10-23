import { AsyncLocalStorage } from 'node:async_hooks';
import { Pool } from 'pg';
import { Queryable, UnitOfWork } from '../../domain/repositories/UnitOfWork';

export class Database implements UnitOfWork<Queryable> {
  private readonly pool: Pool;
  // Opt-in ambient scope: existing explicit transactions retain their behaviour.
  private readonly scope = new AsyncLocalStorage<{client: Queryable; afterCommit: Array<() => Promise<void>>}>();

  constructor(connectionString: string) {
    this.pool = new Pool({ connectionString, connectionTimeoutMillis: 5000, statement_timeout: 30000, query_timeout: 35000 });
  }

  async query<T = any>(text: string, values: unknown[] = []): Promise<{ rows: T[]; rowCount?: number | null }> {
    return (this.scope.getStore()?.client ?? this.pool).query(text, values) as Promise<{ rows: T[]; rowCount?: number | null }>;
  }

  async transaction<R>(work: (ctx: Queryable) => Promise<R>): Promise<R> {
    const active = this.scope.getStore();
    if (active) return work(active.client);
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      const result = await work(client);
      await client.query('COMMIT');
      return result;
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  }


  async atomic<R>(work: () => Promise<R>): Promise<R> {
    if (this.scope.getStore()) return work();
    const afterCommit: Array<() => Promise<void>> = [];
    const result = await this.transaction(client => this.scope.run({client, afterCommit}, work));
    for (const effect of afterCommit) await effect();
    return result;
  }

  async afterCommit(effect: () => Promise<void>): Promise<void> {
    const active = this.scope.getStore();
    if (active) active.afterCommit.push(effect);
    else await effect();
  }

  async close(): Promise<void> {
    await this.pool.end();
  }
}
