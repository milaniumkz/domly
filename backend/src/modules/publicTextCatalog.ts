import {createHash} from 'node:crypto';

/** Public wording only. Never use this shared cache for personalized responses. */
export class PublicTextCatalog {
  private cached?: {body: string; etag: string; expires: number};
  private pending?: Promise<{body: string; etag: string; expires: number}>;
  private generation = 0;
  constructor(private readonly load: () => Promise<unknown[]>, private readonly now = Date.now) {}

  invalidate() {
    this.generation++;
    this.cached = undefined;
    this.pending = undefined;
  }

  async get() {
    if (this.cached && this.cached.expires > this.now()) return this.cached;
    if (this.pending) return this.pending;
    const generation = this.generation;
    const pending = this.load().then(rows => {
      const body = JSON.stringify({ok: true, data: rows});
      const value = {body, etag: '"'+createHash('sha256').update(body).digest('hex')+'"', expires: this.now()+5000};
      if (generation === this.generation) this.cached = value;
      return value;
    });
    this.pending = pending;
    try { return await pending; }
    finally { if (this.pending === pending) this.pending = undefined; }
  }
}
