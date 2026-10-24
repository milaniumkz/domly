const assert=require('assert/strict'),fs=require('fs');
module.exports=async({p,local,session,root})=>{
 const headers={Authorization:'Bearer '+session.accessToken};const before=(await(await local.get('http://127.0.0.1:8082/api/v1/content-pages')).json()).data;
 await p.mouse.move(140,750);await p.mouse.wheel(0,5000);await p.waitForTimeout(500);
 await p.getByText('Настройки',{exact:true}).last().click();await p.waitForTimeout(800);
 await p.mouse.move(900,650);await p.mouse.wheel(0,3000);await p.waitForTimeout(400);
 await p.getByRole('button',{name:'Редактировать политики',exact:true}).click();
 const field=p.getByRole('textbox',{name:'Сумма реферального бонуса',exact:true});await field.click();await field.fill('2111');
 const posts=[];p.on('request',r=>{if(r.method()==='POST')posts.push({path:new URL(r.url()).pathname,body:r.postDataJSON()});});
 await p.screenshot({path:root+'/evidence/settings-before-save-debug.png'});
 try {
  const [response]=await Promise.all([
   p.waitForResponse(r=>r.request().method()==='POST' && /\/admin\/(settings|content-pages)$/.test(new URL(r.url()).pathname),{timeout:30000}),
   p.getByRole('button',{name:'Сохранить',exact:true}).last().click()
  ]);assert.equal(new URL(response.url()).pathname,'/api/v1/admin/settings');assert.equal(response.status(),200);
 } finally {
  fs.writeFileSync(root+'/evidence/server-settings-requests-'+Date.now()+'.json',JSON.stringify({posts,text:await p.locator('body').innerText()},null,2));
  await p.screenshot({path:root+'/evidence/settings-after-save-debug.png'});
 }
 assert.ok(posts.some(r=>r.path==='/api/v1/admin/settings'),'settings editor must save runtime settings, not legal pages');
 assert.ok(!posts.some(r=>r.path.includes('content-pages')),'settings must not overwrite documents');
 const settings=(await(await local.get('http://127.0.0.1:8082/api/v1/admin/settings',{headers})).json()).data;assert.equal(settings.find(r=>r.key==='referralBonusAmount').value,2111);
 const bootstrap=(await(await local.get('http://127.0.0.1:8082/api/v1/app/bootstrap')).json()).data;assert.equal(bootstrap.settings.referralBonusAmount,2111);
 const after=(await(await local.get('http://127.0.0.1:8082/api/v1/content-pages')).json()).data;assert.deepEqual(after,before);
 await p.getByRole('button',{name:'Редактировать политики',exact:true}).click();
 const reopened=p.getByRole('textbox',{name:'Сумма реферального бонуса',exact:true});await reopened.click();assert.equal(await reopened.inputValue(),'2111');
 await p.screenshot({path:root+'/evidence/server-settings-ui-'+Date.now()+'.png'});console.log('PASS admin runtime settings saved to server and legal documents unchanged');
};
