// Run with Playwright installed and a Chromium browser available.
// CHROMIUM_EXECUTABLE=/usr/bin/chromium node scripts/web/install_prompt.browser.test.cjs
// Native install events are simulated; no real installation is performed.
const {chromium,devices}=require('playwright');
const fs=require('fs');
const assert=require('node:assert/strict');
const path=require('node:path');
const script=fs.readFileSync(path.join(__dirname,'../../web/install-prompt.js'),'utf8');
(async()=>{
 const browser=await chromium.launch({...(process.env.CHROMIUM_EXECUTABLE ? {executablePath:process.env.CHROMIUM_EXECUTABLE} : {}),headless:true,args:['--no-sandbox']});
 async function pageFor(options={},init) {
  const context=await browser.newContext(options);
  await context.route('https://install.test/**',route=>route.fulfill({contentType:'text/html',body:'<!doctype html><html><head><base href="/customer/"><meta name="viewport" content="width=device-width, initial-scale=1"></head><body><button id="background">DomLY</button></body></html>'}));
  if(init)await context.addInitScript(init);
  const page=await context.newPage();await page.goto('https://install.test/customer/');await page.addScriptTag({content:script});await page.waitForTimeout(1750);return {page,context};
 }
 let {page,context}=await pageFor({...devices['Pixel 7']});
 await page.locator('#domly-install').waitFor({state:'visible'});
 assert.match(await page.locator('#domly-install-steps').innerText(),/Chrome/);
 assert.equal(await page.locator('[data-install]').isVisible(),false);
 assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),true);

 await page.evaluate(()=>{
  const e=new Event('beforeinstallprompt',{cancelable:true});
  e.prompt=async()=>{window.promptCalls=(window.promptCalls||0)+1;};
  e.userChoice=Promise.resolve({outcome:'dismissed'});dispatchEvent(e);
 });
 assert.equal(await page.locator('[data-install]').isVisible(),true);
 await page.locator('[data-install]').click();
 assert.equal(await page.evaluate(()=>window.promptCalls),1);
 assert.equal(await page.locator('[data-install]').isVisible(),false);
 await page.getByRole('button',{name:'Позже'}).click();
 await page.reload();await page.addScriptTag({content:script});await page.waitForTimeout(1750);
 assert.equal(await page.locator('#domly-install').count(),0);
 await context.close(); console.log('Android: automatic dialog, native prompt, rejection fallback, dismissal and reload passed');
 ({page,context}=await pageFor({...devices['iPhone 13']}));
 assert.match(await page.locator('#domly-install-steps').innerText(),/Поделиться.*Домой/);
 await page.evaluate(()=>{document.documentElement.style.fontSize='24px';document.querySelector('#domly-install').style.fontSize='24px'});
 assert.equal(await page.evaluate(()=>document.querySelector('#domly-install').scrollWidth<=document.querySelector('#domly-install').clientWidth),true);

 await page.keyboard.press('Escape');assert.equal(await page.locator('#domly-install').isVisible(),false);
 await context.close();console.log('iPhone: Safari instructions, large text and keyboard dismissal passed');
 ({page,context}=await pageFor({},()=>{const original=window.matchMedia;window.matchMedia=q=>q==='(display-mode: standalone)'?{matches:true,addEventListener(){}}:original(q);}));
 assert.equal(await page.locator('#domly-install').count(),0);await context.close();console.log('Installed standalone: no prompt passed');
 ({page,context}=await pageFor({...devices['Pixel 7']}));
 await page.evaluate(()=>{
  const e=new Event('beforeinstallprompt',{cancelable:true});e.prompt=async()=>{};e.userChoice=Promise.resolve({outcome:'accepted'});dispatchEvent(e);
 });
 await page.locator('[data-install]').click();assert.equal(await page.locator('#domly-install').isVisible(),false);
 await context.close();console.log('Accepted installation: closes prompt passed');
 await browser.close();
})().catch(e=>{console.error(e);process.exit(1)});
