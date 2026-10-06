import { Pool } from 'pg';
import { Queryable, UnitOfWork } from '../../domain/repositories/UnitOfWork';

export class Database implements UnitOfWork<Queryable> {
  private readonly pool: Pool;

  constructor(connectionString: string) {
    this.pool = new Pool({ connectionString });
  }

  async query<T = any>(text: string, values: unknown[] = []): Promise<{ rows: T[]; rowCount?: number | null }> {
    return this.pool.query(text, values) as Promise<{ rows: T[]; rowCount?: number | null }>;
  }

  async transaction<R>(work: (ctx: Queryable) => Promise<R>): Promise<R> {
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

  async close(): Promise<void> {
    await this.pool.end();
  }
}
