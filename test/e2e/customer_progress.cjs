const fs=require('fs'),assert=require('assert/strict');
module.exports=async({p,local,session,root})=>{
 const headers={Authorization:'Bearer '+session.accessToken};
 const me=(await (await local.get('http://127.0.0.1:8082/api/v1/me',{headers})).json()).data;
 const packages=(await (await local.get('http://127.0.0.1:8082/api/v1/packages/my',{headers})).json()).data;
 const active=packages.find(x=>x.status==='active');
 assert.ok(me.monthly_spent>0,'fixture must contain actual paid services');
 const kk=me.language==='kk';
 const tier={NEWBIE:kk?'Біздің сүйікті Жаңадан бастаушы':'Наш любимый Новичок',CLEANSTER:kk?'Біздің сүйікті ұқыпты жігітіміз':'Наш любимый чистюля',GURU:kk?'Тазалық гуруы':'Гуру чистоты',GOD:kk?'Тазалық құдайы':'Бог чистоты'}[me.tier];
 const body=await p.locator('body').innerText();
 assert.ok(body.includes(String(me.monthly_spent)), 'actual monthly paid amount is displayed');
 assert.ok(body.includes(String(me.next_tier_threshold)), 'configured next threshold is displayed');
 assert.ok(body.toLowerCase().includes(tier.toLowerCase()), 'calculated level is displayed');
 assert.ok(body.includes(String(active.purchase_config.monthlyPrice)), 'stored subscription price is displayed');
 const card=p.getByRole('button',{name:new RegExp(kk?'^Сіздің үлгеріміңіз':'^Ваш прогресс')}).first();
 for(let n=0;n<12;n++){const box=await card.boundingBox();if(box&&box.y>0&&box.y<750)break;await p.mouse.move(250,650);await p.mouse.wheel(0,200);await p.waitForTimeout(200);}
 await p.screenshot({path:root+'/evidence/progress-price-'+me.language+'.png'});
 await card.click();await p.waitForTimeout(400);
 const details=await p.locator('body').innerText();assert.ok(details.includes(kk?'Шақырылған клиенттер':'Приглашённые клиенты'));
 const evidence={language:me.language,monthlySpent:me.monthly_spent,tier:me.tier,nextThreshold:me.next_tier_threshold,progress:me.tier_progress,subscriptionPrice:active.purchase_config.monthlyPrice,status:'passed'};
 fs.writeFileSync(root+'/evidence/progress-price-'+me.language+'.json',JSON.stringify(evidence,null,2));console.log(evidence);
};
