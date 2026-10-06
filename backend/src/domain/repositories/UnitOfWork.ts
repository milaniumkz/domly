export interface Queryable {
  query<T = any>(text: string, values?: unknown[]): Promise<{ rows: T[]; rowCount?: number | null }>;
}

export interface UnitOfWork<T = Queryable> {
  transaction<R>(work: (ctx: T) => Promise<R>): Promise<R>;
}
