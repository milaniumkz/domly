import test from 'node:test';
import assert from 'node:assert/strict';
import jwt from 'jsonwebtoken';
import { env } from '../common/env';
import { signAccessToken, signRefreshToken, verifyAccessToken, verifyRefreshToken, requestIdentity } from '../common/auth';
const user = {id:'00000000-0000-4000-8000-000000000001',phone:'+70000000000',role:'customer' as const};
test('prepared HMAC keys preserve existing tokens and reject invalid credentials', () => {
  assert.equal(verifyAccessToken(jwt.sign(user,env.jwtAccessSecret,{expiresIn:60})).id,user.id);
  assert.equal(verifyRefreshToken(jwt.sign(user,env.jwtRefreshSecret,{expiresIn:60})).id,user.id);
  assert.equal((jwt.verify(signAccessToken(user),env.jwtAccessSecret) as any).role,'customer');
  assert.equal((jwt.verify(signRefreshToken(user),env.jwtRefreshSecret) as any).role,'customer');
  for (const token of [jwt.sign(user,'different-secret',{expiresIn:60}),jwt.sign(user,env.jwtAccessSecret,{expiresIn:-1}),jwt.sign(user,env.jwtAccessSecret,{algorithm:'none'})]) assert.throws(()=>verifyAccessToken(token));
  assert.throws(()=>verifyRefreshToken(jwt.sign(user,env.jwtRefreshSecret,{expiresIn:-1})));
  assert.throws(()=>verifyRefreshToken(jwt.sign({...user,role:'invented'},env.jwtRefreshSecret)));
});

test('request identity reuse is isolated by request, token and database and retries failed reads', async () => {
  let calls=0,fail=false;
  const db:any={query:async(_sql:string,values:string[])=>{calls++;if(fail)throw Error('offline');return{rows:[{id:values[0],role:'customer'}]};}};
  const req:any={},token=signAccessToken(user);
  const results=await Promise.all([requestIdentity(req,db,token),requestIdentity(req,db,token)]);
  assert.equal(calls,1);assert.equal(results[0].account.id,user.id);
  const other={...user,id:'00000000-0000-4000-8000-000000000002'};
  assert.equal((await requestIdentity(req,db,signAccessToken(other))).account.id,other.id);
  assert.equal(calls,2);
  await requestIdentity({} as any,db,token);assert.equal(calls,3);
  await requestIdentity(req,{query:db.query} as any,token);assert.equal(calls,4);
  const retry:any={};fail=true;await assert.rejects(requestIdentity(retry,db,token));
  fail=false;await requestIdentity(retry,db,token);assert.equal(calls,6);
  await assert.rejects(requestIdentity(req,db,'invalid'));assert.equal(calls,6);
});
