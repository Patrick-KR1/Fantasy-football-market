import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {mkdir,writeFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import {loadTs} from './load-ts.mjs';
const {chromium}=await import(pathToFileURL(resolve(process.env.KICKX_BROWSER_MODULE||'/tmp/kickx-browser','node_modules/playwright/index.mjs')).href);
const mock=loadTs('../server/kickx/mock-data.ts',{'server-only':{},'@/lib/kickx/squad':loadTs('../lib/kickx/squad.ts')});
const base='http://localhost:3113',server=spawn(process.execPath,['node_modules/next/dist/bin/next','start','-H','localhost','-p','3113'],{stdio:'ignore'});
let browser;const checks=[],errors=[];
try{
 for(let i=0;i<40;i++){try{if((await fetch(base)).ok)break;}catch{}if(i===39)throw Error('App did not start');await new Promise(r=>setTimeout(r,500));}
 await mkdir('test-artifacts',{recursive:true});browser=await chromium.launch({executablePath:process.env.KICKX_CHROMIUM_PATH||undefined});
 for(const width of[320,390,768,1440]){
  let state=structuredClone({...mock.mockPublicData(),session:mock.mockSession,member:mock.mockMemberData()});
  const team=state.teams.find(t=>t.id===state.session.profile.primaryTeam),other=state.teams.find(t=>t.id!==team.id);
  const now=new Date().toISOString(),future=i=>new Date(Date.now()+i*86400000).toISOString();
  const match=(i,past=false)=>({id:`browser-match-${past?'p':'u'}${i}`,homeId:team.id,awayId:other.id,homeName:team.name,awayName:other.name,startsAt:future(past?-i:i),status:past?'FT':'NS',homeScore:past?2:null,awayScore:past?1:null,penaltiesHome:null,penaltiesAway:null,leagueName:'Premier League',canPredict:!past,choice:null,actual:past?'win':null,reward:null,settledAt:null});
  let predictions={teamId:team.id,teamName:team.name,serverTime:now,upcoming:[1,2,3].map(i=>match(i)),past:[1,2,3].map(i=>match(i,true))};
  predictions.past[0]={...predictions.past[0],choice:'win',reward:5000,settledAt:now};
  predictions.past[1]={...predictions.past[1],choice:'loss',reward:1000,settledAt:now};
  let posts=0,deny=false;
  const context=await browser.newContext({viewport:{width,height:960},timezoneId:'Asia/Seoul'});
  await context.addInitScript(()=>localStorage.setItem('kickx:price-reveal','off'));
  await context.route('**/api/**',async route=>{
   const req=route.request(),u=new URL(req.url());
   if(u.pathname==='/api/kickx')return route.fulfill({json:{status:'ready',data:state}});
   if(u.pathname==='/api/kickx/predictions'){
    if(req.method()==='POST'){
     posts++;if(deny)return route.fulfill({status:409,json:{error:'경기가 시작되어 예측이 마감되었습니다.'}});
     const body=req.postDataJSON();assert.equal(body.userId,undefined);predictions.upcoming=predictions.upcoming.map(m=>m.id===body.fixtureId?{...m,choice:body.choice}:m);
     return route.fulfill({json:predictions});
    }
    return route.fulfill({json:{status:'ready',data:predictions}});
   }
   if(u.pathname==='/api/kickx/notifications')return route.fulfill({json:{status:'ready',data:u.searchParams.has('summary')?{hasUnread:true,matchNotifications:true,commentNotifications:true,replyNotifications:true}:{items:[{id:'777',kind:'prediction',homeName:team.name,awayName:other.name,predictionChoice:'win',predictionActual:'win',predictionReward:5000,fixtureId:'browser-match-p1',createdAt:now,readAt:null}],hasMore:false,hasUnread:true}}});
   return route.fulfill({json:{status:'ready',data:{items:[],past:[],upcoming:[],daily:{items:[]},weekly:{items:[]},catalog:[],inventory:{},loadout:{},unclaimedDaily:[],attendance:[]}}});
  });
  const page=await context.newPage();page.on('pageerror',error=>errors.push(error.message));
  await page.goto(base+'/predictions',{waitUntil:'networkidle'});
  await page.locator('.prediction-card').first().waitFor();
  assert.equal(await page.locator('.prediction-card').count(),6);
  assert.match(await page.locator('.prediction-result.success').innerText(),/예측 성공[\s\S]*5,000 P 지급 완료/);
  assert.match(await page.locator('.prediction-result.miss').innerText(),/예측 실패[\s\S]*1,000 P 지급 완료/);
  assert.match(await page.locator('.prediction-result.no-pick').innerText(),/미참여/);
  const upcoming=page.getByRole('region',{name:'다가오는 3경기'}),first=upcoming.locator('.prediction-card').first();
  await first.getByRole('button',{name:'승 승리'}).click();
  await page.waitForFunction(()=>document.querySelector('.prediction-options button:first-child')?.getAttribute('aria-pressed')==='true');
  await first.getByRole('button',{name:'무 무승부'}).click();
  await page.waitForFunction(()=>document.querySelector('.prediction-options button:nth-child(2)')?.getAttribute('aria-pressed')==='true');
  assert.equal(posts,2);
  deny=true;await first.getByRole('button',{name:'패 패배'}).click();await page.getByText('경기가 시작되어 예측이 마감되었습니다.',{exact:true}).waitFor();
  predictions.upcoming[1]={...predictions.upcoming[1],canPredict:false,startsAt:new Date(Date.now()-60000).toISOString()};
  await page.getByRole('button',{name:'새로고침',exact:true}).click();
  await page.waitForFunction(()=>document.querySelectorAll('.prediction-options')[1]?.querySelector('button')?.disabled);
  assert.equal(await upcoming.locator('.prediction-card').nth(1).getByRole('button',{name:'승 승리'}).isDisabled(),true);
  await page.getByRole('button',{name:/알림함 ·/}).click();
  await page.getByRole('link',{name:/경기 예측 성공/}).waitFor();assert.equal(await page.getByRole('link',{name:/경기 예측 성공/}).getAttribute('href'),'/predictions');
  await page.getByRole('button',{name:'알림함 닫기'}).click();
  const overflow=await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth);assert.equal(overflow,false,`${width}px page overflow`);
  await page.screenshot({path:`test-artifacts/predictions-${width}.png`,fullPage:true});
  // Changing account must discard all prior member picks immediately.
  state={...state,session:null,member:null};await page.reload({waitUntil:'networkidle'});
  assert.equal(await page.locator('.prediction-card').count(),0);await page.getByText('로그인 후 내 정보를 확인할 수 있습니다.',{exact:true}).waitFor();
  checks.push({width,cards:6,saveAndChange:true,deadlineError:true,closedDisabled:true,inbox:true,guestPrivacy:true,overflow:false});await context.close();
 }
 assert.deepEqual(errors,[]);await writeFile('test-artifacts/predictions-browser.json',JSON.stringify(checks,null,2));console.log(JSON.stringify(checks,null,2));
}finally{await browser?.close();server.kill();}
