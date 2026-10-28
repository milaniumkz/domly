const assert=require('node:assert/strict'),fs=require('fs');
module.exports=async({p,root})=>{
 const errors=[];p.on('pageerror',e=>errors.push(e.message));
 p.on('console',m=>{if(/Bad state|Another exception/.test(m.text()))errors.push(m.text());});
 p.__homeState='multi';await p.goto('https://domly.kz/customer/#/client/home');
 await p.waitForSelector('flutter-view',{state:'attached'});await p.waitForTimeout(1600);
 await p.evaluate(()=>document.querySelector('flt-semantics-placeholder')?.click());
 await p.getByText('Уборка 1 из 4',{exact:true}).waitFor();
 for(let n=1;n<=4;n++){
  const text=await p.locator('body').innerText();assert(text.includes(n+' ноября 2026'));
  assert(text.includes('Осталось 4 уборки'));assert(text.includes('Заказать уборку'));
  assert(text.includes(n===2?'Ваша уборка назначена':'Подбираем исполнителя'));
  await p.screenshot({path:root+'/evidence/manual-pager-'+n+'.png'});
  if(n<4){await p.mouse.move(315,430);await p.mouse.down();await p.mouse.move(70,430,{steps:12});await p.mouse.up();
   await p.getByText('Уборка '+(n+1)+' из 4',{exact:true}).waitFor();}
 }
 await p.waitForTimeout(6000);assert((await p.locator('body').innerText()).includes('Уборка 4 из 4'));
 await p.mouse.wheel(0,450);await p.waitForTimeout(300);
 await p.screenshot({path:root+'/evidence/manual-pager-balance.png'});
 await p.getByText('Заказать уборку',{exact:true}).click();
 await p.waitForFunction(()=>location.hash.includes('/client/package-calendar'));
 assert.equal(errors.length,0,errors.join('\n'));
 fs.writeFileSync(root+'/manual-pager-result.json',JSON.stringify({pages:4,noAutoplay:true,calendarOpened:true,errors}));
};
