const assert=require('node:assert/strict'),fs=require('fs');
module.exports=async({p,root})=>{
 const errors=[];p.on('console',m=>{if(/already been listened|Another exception|Bad state/.test(m.text()))errors.push(m.text());});p.on('pageerror',e=>errors.push(e.message));
 p.__homeState='none';await p.goto('https://domly.kz/customer/#/client/home');await p.waitForSelector('flutter-view',{state:'attached'});await p.waitForTimeout(1800);await p.evaluate(()=>document.querySelector('flt-semantics-placeholder')?.click());
 for(let i=0;i<3;i++){
 await p.getByText('Выбрать пакет',{exact:true}).first().click();await p.getByText('Выберите пакет',{exact:true}).waitFor();await p.waitForTimeout(1200);
 const text=await p.locator('body').innerText();fs.writeFileSync(root+'/picker-stream-text.txt',text);
 await p.screenshot({path:root+'/evidence/picker-stream-'+i+'.png'});
 assert.equal(errors.length,0,errors.join('\n'));assert(/Разов|Кварталь|Генераль/.test(text),'catalog cards must be visible');
 await p.keyboard.press('Escape');await p.waitForTimeout(400);
 }
 fs.writeFileSync(root+'/picker-stream-result.json',JSON.stringify({opens:3,errors}));
};
