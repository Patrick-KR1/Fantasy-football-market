import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { mkdir, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { loadTs } from './load-ts.mjs';
const { chromium } = await import(pathToFileURL(resolve(process.env.KICKX_BROWSER_MODULE || '/tmp/kickx-browser', 'node_modules/playwright/index.mjs')).href);
const { emptyPlatformData } = loadTs('../lib/kickx/data.ts');
const base='http://localhost:3118',out='test-artifacts/market-stats';
const server=spawn(process.execPath,['node_modules/next/dist/bin/next','start','-H','localhost','-p','3118'],{stdio:'ignore'});
const report={flows:[],errors:[]};let browser;
try {
 for(let i=0;i<40;i++){try{if((await fetch(base)).ok)break;}catch{}if(i===39)throw Error('App did not start');await new Promise(r=>setTimeout(r,500));}
 browser=await chromium.launch({executablePath:process.env.KICKX_BROWSER_EXECUTABLE||undefined});
 await mkdir(out,{recursive:true});
 for(const width of [1440,768,390]){
  const players=[['known','기록 선수',15,3],['zero','무득점 선수',0,0],['unknown','미확인 선수',null,null]].map(([id,name,goals,assists],i)=>({id,name,english:name,position:'MF',price:100000,change:0,performance:8,volume:99-i,team:'club',goals,assists,statsScope:'imported_matches',importedMatches:11,history:[],records:[],analysis:null}));
  const state={...emptyPlatformData(),players,teams:[{id:'club',name:'테스트 구단',leagueId:'bsd-1'}],leagues:[{id:'bsd-1',name:'Premier League'}]};
  const context=await browser.newContext({viewport:{width,height:960},timezoneId:'Asia/Seoul'});
  await context.route(/^https:\/\//,r=>r.abort());
  await context.route('**/api/**',route=>{
   const url=new URL(route.request().url()),path=url.pathname;
   const ready=data=>route.fulfill({json:{status:'ready',source:'database',data}});
   if(path==='/api/kickx')return ready(state);
   if(path==='/api/kickx/players'){
    const q=url.searchParams.get('q')||'',page=Number(url.searchParams.get('page')||1),size=Number(url.searchParams.get('size')||12),items=players.filter(p=>p.name.includes(q));
    return ready({items:items.slice((page-1)*size,page*size),total:items.length,page,size});
   }
   if(path==='/api/kickx/shop')return ready({catalog:[],poolSize:0});
   return ready({items:[],total:0,page:1,size:20});
  });
  const page=await context.newPage();page.on('pageerror',e=>report.errors.push(e.message));
  await page.goto(base+'/market',{waitUntil:'domcontentloaded'});
  const card=page.locator('.pcard').filter({has:page.getByRole('heading',{name:'기록 선수',exact:true})});
  await card.waitFor();
  assert.equal(await card.locator('.pcard-facts > div').nth(1).locator('dd').innerText(),'15');
  assert.equal(await card.locator('.pcard-facts > div').nth(2).locator('dd').innerText(),'3');
  const zero=page.locator('.pcard').filter({has:page.getByRole('heading',{name:'무득점 선수',exact:true})});
  assert.equal(await zero.locator('.pcard-facts > div').nth(1).locator('dd').innerText(),'0');
  await page.screenshot({path:`${out}/cards-${width}.png`,fullPage:true});
  await page.getByRole('button',{name:'목록 보기',exact:true}).click();
  const table=page.locator('.market-table');await table.waitFor();
  const headers=await table.locator('th').allTextContents();
  assert(headers.includes('골')&&headers.includes('도움'));assert(!headers.includes('거래량'));
  for(const [id,goals,assists]of [['known','15','3'],['zero','0','0'],['unknown','—','—']]){
   const row=table.locator('tr').filter({has:page.locator(`a[href="/players/${id}"]`)});
   await row.waitFor();const cells=await row.locator('td').allTextContents();
   assert.equal(cells[headers.indexOf('골')],goals);assert.equal(cells[headers.indexOf('도움')],assists);
  }
  if(width>=768){assert(await table.locator('th').nth(headers.indexOf('골')).isVisible());assert(await table.locator('th').nth(headers.indexOf('도움')).isVisible());}
  assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1));
  await page.screenshot({path:`${out}/list-${width}.png`,fullPage:true});
  report.flows.push({width,cardGoals:15,cardAssists:3,zeroPreserved:true,unknownPreserved:true,volumeColumnRemoved:true});
  await context.close();
 }
 assert.deepEqual(report.errors,[]);console.log(JSON.stringify(report));
}finally{await mkdir(out,{recursive:true});await writeFile(`${out}/report.json`,JSON.stringify(report,null,2));await browser?.close();server.kill('SIGTERM');}
