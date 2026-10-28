const fs=require('fs'),assert=require('node:assert/strict');
module.exports=async({p,root})=>{
 const states={none:'Начните с чистого дома',invoice:'Заявка отправлена',unpaid:'Пакет ждёт оплаты',failed:'Не удалось оплатить',paid:'Запланируйте уборку',search:'Подбираем исполнителя',assigned:'Ваша уборка назначена',progress:'Наводим чистоту',completed:'Дома снова чисто',cancelled:'Уборка отменена',frozen:'Пакет на паузе',used:'Продолжим заботу о доме?'};
 const rows=[];for(const [state,title] of Object.entries(states)){
 p.__homeState=state;await p.goto('https://domly.kz/customer/?reference='+state+'#/client/home',{waitUntil:'domcontentloaded'});await p.waitForSelector('flutter-view',{state:'attached',timeout:60000});await p.waitForTimeout(1600);await p.evaluate(()=>document.querySelector('flt-semantics-placeholder')?.click());await p.getByText(title,{exact:true}).first().waitFor({timeout:25000});await p.waitForTimeout(250);
 const text=await p.locator('body').innerText();assert(text.includes('Дополнительные услуги'));assert(text.includes('Пригласить друга'));
 if(state==='used')assert(text.includes('Выполнено 4 из 4'));
 if(state==='completed')assert(text.includes('Использовано 1 из 4'));
 await p.screenshot({path:root+'/evidence/reference-'+state+'.png'});
 if(state==='failed'||state==='unpaid'){
 await p.getByText(state==='failed'?'Попробовать снова':'Оплатить',{exact:true}).first().click();
 await p.getByText('Выберите способ оплаты',{exact:true}).waitFor();
 assert((await p.locator('body').innerText()).includes('10 000'));
 }
 if(state==='assigned'){
 await p.getByText('Алия Ваш исполнитель',{exact:true}).click();
 await p.getByText('Алия',{exact:true}).waitFor();
 }
 rows.push({state,title,text,status:'passed'});console.log(JSON.stringify({state,status:'passed'}));
 }
 fs.writeFileSync(root+'/reference-ui-results.json',JSON.stringify(rows,null,2));
};
