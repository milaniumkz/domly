import test from 'node:test';
import assert from 'node:assert/strict';
import jwt from 'jsonwebtoken';
import { env } from '../common/env';
import { signAccessToken, signRefreshToken, verifyAccessToken, verifyRefreshToken } from '../common/auth';
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
