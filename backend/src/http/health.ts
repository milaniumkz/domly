import {RequestHandler} from 'express';
import {Queryable} from '../domain/repositories/UnitOfWork';
import {ok} from '../common/api';

// A dependency timeout must fail the probe, not terminate the API process.
export function healthHandler(db: Queryable): RequestHandler {
  return (_req, res) => {
    void db.query('SELECT 1').then(() => {
      ok(res, {status: 'ok', service: 'domly-backend', time: new Date().toISOString()});
    }).catch(() => {
      res.status(503).json({ok: false, error: {code: 'dependency_unavailable', message: 'Сервис временно недоступен.'}});
    });
  };
}
