import { availableParallelism } from 'node:os';
import { Worker } from 'node:worker_threads';
import { ApiError } from './api';

type Task = { operation: 'hash' | 'compare'; value: string; argument: string | number; resolve: (value: any) => void; reject: (error: Error) => void };
type Slot = { worker: Worker; task?: Task; dead?: boolean };
const workerSource = `
  const {parentPort,workerData}=require('node:worker_threads');
  const bcrypt=require(workerData.module);
  parentPort.on('message',({operation,value,argument})=>{
    try { parentPort.postMessage({result:operation==='hash'?bcrypt.hashSync(value,argument):bcrypt.compareSync(value,argument)}); }
    catch { parentPort.postMessage({failed:true}); }
  });
`;

/** CPU work is bounded and isolated from HTTP/DB/SSE processing. No hash result
 * is cached, and the existing bcrypt work factors and formats are unchanged. */
export class PasswordCryptoPool {
  private slots: Slot[] = [];
  private queue: Task[] = [];
  private closed = false;
  constructor(private readonly size = Math.max(1, Math.min(4, availableParallelism())), private readonly capacity = 2048) {}

  run(operation: Task['operation'], value: string, argument: string | number): Promise<any> {
    if (this.closed || this.queue.length + this.slots.filter(s=>s.task).length >= this.capacity) {
      return Promise.reject(new ApiError(503, 'authentication_busy', 'Сервис входа занят. Повторите попытку позже.'));
    }
    return new Promise((resolve,reject)=>{this.queue.push({operation,value,argument,resolve,reject});this.pump();});
  }

  private pump() {
    if (this.closed) return;
    while (this.queue.length) {
      let slot = this.slots.find(s=>!s.task);
      if (!slot) {
        if (this.slots.length >= this.size) return;
        try {
          slot = {worker:new Worker(workerSource,{eval:true,workerData:{module:require.resolve('bcryptjs')}})};
        } catch {
          this.queue.shift()!.reject(new Error('Password worker unavailable'));
          continue;
        }
        const current = slot;
        this.slots.push(current);
        current.worker.on('message',message=>{
          const task=current.task;current.task=undefined;current.worker.unref();
          if (message.failed) task?.reject(new Error('Password operation failed'));
          else task?.resolve(message.result);
          this.pump();
        });
        const failed=()=>{
          if(current.dead)return;current.dead=true;
          this.slots=this.slots.filter(s=>s!==current);
          current.task?.reject(new Error('Password worker unavailable'));current.task=undefined;
          this.pump();
        };
        current.worker.on('error',failed);
        current.worker.on('exit',failed);
      }
      slot.task=this.queue.shift()!;slot.worker.ref();
      const {operation,value,argument}=slot.task;
      slot.worker.postMessage({operation,value,argument});
    }
  }

  async close() {
    this.closed=true;
    for(const task of this.queue.splice(0))task.reject(new Error('Password pool closed'));
    await Promise.all(this.slots.map(s=>s.worker.terminate()));
  }
}

const pool = new PasswordCryptoPool();
export const passwordCrypto = {
  hash: (value: string, rounds: number): Promise<string> => pool.run('hash',value,rounds),
  compare: (value: string, hash: string): Promise<boolean> => pool.run('compare',value,hash),
};
