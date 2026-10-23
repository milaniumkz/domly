import test from 'node:test';
import assert from 'node:assert/strict';
import bcrypt from 'bcryptjs';
import { PasswordCryptoPool } from '../common/passwordCrypto';

test('worker bcrypt preserves hashes and keeps timers responsive under parallel hashing', async()=>{
  const pool=new PasswordCryptoPool(2);
  let ticks=0;const timer=setInterval(()=>ticks++,5);
  try{
    const hashes=await Promise.all(Array.from({length:20},(_,i)=>pool.run('hash','test-password-'+i,8)));
    assert.ok(ticks>2,'HTTP event loop must remain responsive during CPU work');
    for(let i=0;i<hashes.length;i++){
      assert.equal(bcrypt.getRounds(hashes[i]),8);
      assert.ok(await pool.run('compare','test-password-'+i,hashes[i]));
      assert.equal(await pool.run('compare','wrong-password',hashes[i]),false);
    }
    const legacy=bcrypt.hashSync('legacy-password',8);
    assert.ok(await pool.run('compare','legacy-password',legacy));
    assert.ok(bcrypt.compareSync('test-password-0',hashes[0]));
  }finally{clearInterval(timer);await pool.close();}
});

test('authentication CPU queue is bounded and does not accept unlimited work',async()=>{
  const pool=new PasswordCryptoPool(1,1);
  try{
    const accepted=pool.run('hash','test-password',8);
    await assert.rejects(pool.run('hash','another-password',8),{code:'authentication_busy'});
    await accepted;
    assert.ok(await pool.run('compare','test-password',await pool.run('hash','test-password',8)));
  }finally{await pool.close();}
});
