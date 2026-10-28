const fs=require('fs'),assert=require('node:assert/strict');
module.exports=async({p,root})=>{
 const states={none:'Чистый дом начинается здесь',invoice:'Ожидание счёта',unpaid:'Ожидание оплаты',failed:'Оплата не завершена',paid:'Запланируйте уборку',search:'Ищем исполнителя',assigned:'Уборка назначена',progress:'Уборка идёт',completed:'Уборка завершена',cancelled:'Уборка отменена',frozen:'Пакет заморожен',used:'Пакет использован'};
 const results=[];
 async function open(state){
  p.__homeState=state;
  await p.goto('https://domly.kz/customer/?state='+state+'#/client/home',{waitUntil:'domcontentloaded'});
  await p.waitForSelector('flutter-view',{state:'attached',timeout:60000});
  await p.waitForTimeout(2000);
  await p.evaluate(()=>document.querySelector('flt-semantics-placeholder')?.click());
  await p.getByText(states[state],{exact:true}).first().waitFor({timeout:30000});
  await p.waitForTimeout(2000);
 }
 for(const [state,heading] of Object.entries(states)){
  await open(state);
  const text=await p.locator('body').innerText();assert(text.includes(heading));
  assert(!text.includes('Не удалось открыть главный экран'));
  if(['none','paid'].includes(state))assert(!text.includes('Подтверждено'));
  if(['unpaid','failed'].includes(state))assert(text.includes('10 000 ₸'));
  if(state==='frozen')assert(!text.includes('Выбрать дату и время'));
  await p.screenshot({path:root+'/evidence/'+state+'.png'});
  results.push({state,heading,status:'passed',text});console.log(JSON.stringify({state,status:'passed'}));
 }
 const actions=[];
 for(const [state,label,route] of [['paid','Выбрать дату и время','package-calendar'],['frozen','Мой пакет','package-calendar'],['unpaid','Детали оплаты','orders'],['assigned','Детали уборки','orders'],['completed','Детали','orders']]){
  await open(state);await p.getByRole('button',{name:label,exact:true}).click();await p.waitForTimeout(1600);
  assert(p.url().includes('/client/'+route),state+': expected '+route+' got '+p.url());actions.push({state,label,route,status:'passed'});
 }
 await open('assigned');await p.getByRole('button',{name:'Отменить',exact:true}).click();await p.getByText('Отменить уборку?',{exact:true}).waitFor();await p.getByRole('button',{name:'Нет',exact:true}).click();actions.push({state:'assigned',label:'Отменить',status:'confirmation opened and dismissed; no mutation'});
 await open('none');await p.getByRole('button',{name:'Выбрать пакет',exact:true}).first().click();await p.waitForTimeout(800);const picker=await p.locator('body').innerText();assert(picker.includes('Выберите пакет') && picker.includes('Сразу откроем оформление заказа по выбранному пакету.'));actions.push({state:'none',label:'Выбрать пакет',status:'opened'});
 await p.setViewportSize({width:320,height:900});await open('paid');await p.screenshot({path:root+'/evidence/paid-320.png'});
 fs.writeFileSync(root+'/states-results.json',JSON.stringify({states:results,actions,verifiedAt:new Date().toISOString()},null,2));
};
