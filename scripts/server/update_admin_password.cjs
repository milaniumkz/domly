// Input is passed privately through stdin; never log the phone or hash.
const fs = require('fs');
const {Pool} = require('pg');
(async () => {
  const input = JSON.parse(fs.readFileSync(0, 'utf8'));
  if (!/^\+?[0-9]{10,15}$/.test(input.phone || '') || !/^\$2[aby]\$[0-9]{2}\$[./A-Za-z0-9]{53}$/.test(input.hash || '')) {
    throw new Error('Invalid password rotation input');
  }
  const pool = new Pool({connectionString: process.env.DATABASE_URL});
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const result = await client.query("SELECT id FROM app_users WHERE phone=$1 AND role IN ('admin','superadmin') AND status <> 'deleted' FOR UPDATE", [input.phone]);
    if (result.rowCount !== 1) throw new Error('Expected exactly one existing admin account');
    await client.query('UPDATE app_users SET password_hash=$2, updated_at=NOW() WHERE id=$1', [result.rows[0].id, input.hash]);
    await client.query('COMMIT');
    console.log('Existing admin password updated successfully');
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
    await pool.end();
  }
})().catch(() => { console.error('Admin password update failed'); process.exitCode = 1; });
