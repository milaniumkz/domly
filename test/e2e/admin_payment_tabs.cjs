const fs=require('fs'),assert=require('assert/strict');
module.exports=async({p,root})=>{
p.setDefaultTimeout(15000);
await p.getByText('Платежи',{exact:true}).first().click();
await p.getByText('Операционный центр / Платежи',{exact:true}).waitFor();
await p.getByRole('textbox').first().fill('Аудит вкладок 20261024');await p.waitForTimeout(1500);
await p.screenshot({path:root+'/evidence/admin-tabs-search.png'});
await p.getByLabel(/Ожидает оплату/).click();await p.waitForTimeout(1500);
const text=await p.locator('body').innerText();const after=process.env.AUDIT_PHASE==='after';
await p.screenshot({path:root+'/evidence/admin-payment-tabs-'+(after?'after':'before')+'.png'});
if(after){assert.ok(!text.includes('Создано: —'),'REST payment dates must be visible');assert.equal(await p.getByLabel('Ожидает оплату (1)',{exact:true}).count(),1);assert.ok(!text.includes('Платежи не найдены'));for(const [tab,count] of [['Оплаченные',60],['Отменённые',2],['Ошибки',1]]){await p.getByLabel(tab+' ('+count+')',{exact:true}).click();await p.waitForTimeout(1200);assert.ok(!(await p.locator('body').innerText()).includes('Платежи не найдены'));if(tab==='Оплаченные'){for(let i=0;i<80;i++){if(await p.getByText('Показать ещё',{exact:true}).isVisible().catch(()=>false))break;await p.mouse.move(900,600);await p.mouse.wheel(0,700);await p.waitForTimeout(60);}const next=p.waitForResponse(r=>r.url().includes('/admin/payment-history')&&r.url().includes('limit=100'));await p.getByText('Показать ещё',{exact:true}).click();assert.equal((await (await next).json()).data.items.length,60);}}}
else{assert.equal(await p.getByLabel('Ожидает оплату (0)',{exact:true}).count(),1);assert.match(text,/Платежи не найдены/);}
fs.writeFileSync(root+'/evidence/admin-payment-tabs-'+(after?'after':'before')+'.json',JSON.stringify({after,text},null,2));console.log(after?'All payment tabs find older records':'Reproduced: older pending payment is hidden');
};
