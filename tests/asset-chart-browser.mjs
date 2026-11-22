import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { mkdir, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { loadTs } from './load-ts.mjs';
const { chromium } = await import(pathToFileURL(resolve(process.env.KICKX_BROWSER_MODULE || '/tmp/kickx-browser','node_modules/playwright/index.mjs')).href);
const { emptyPlatformData } = loadTs('../lib/kickx/data.ts');
const base='http://localhost:3119',out='test-artifacts/asset-chart';
const server=spawn(process.execPath,['node_modules/next/dist/bin/next','start','-H','localhost','-p','3119'],{stdio:'ignore'});
const values=[1000000,1008000,995000,1014000,1031000,1022000,1045000,1018000,1029000,1061000,1042000,1055000,1083000,1067000,1039000,1058000,1094000,1112000,1086000,1068000,1103000,1138000,1114000,1149000,1163000,1127000,1109000,1142000,1184000,1201000,1169000,1148000,1189000,1218000,1192000,1164000,1205000,1246000,1211000,1233000];
const report={layouts:[],errors:[]};let browser;
async function coverage(line,legacy=false){
 return line.evaluate(async(path,legacy)=>{
  const svg=path.ownerSVGElement,rect=svg.getBoundingClientRect(),box=svg.viewBox.baseVal;
  const style=getComputedStyle(path),ns='http://www.w3.org/2000/svg';
  const imageSvg=document.createElementNS(ns,'svg');
  imageSvg.setAttribute('xmlns',ns);imageSvg.setAttribute('viewBox',svg.getAttribute('viewBox'));
  imageSvg.setAttribute('width',String(Math.ceil(rect.width)));imageSvg.setAttribute('height',String(Math.ceil(rect.height)));
  imageSvg.setAttribute('preserveAspectRatio','none');
  const paint=path.cloneNode(true);paint.removeAttribute('class');paint.removeAttribute('style');
  for(const [name,value]of Object.entries({'stroke':style.stroke,'stroke-width':style.strokeWidth,'stroke-linecap':style.strokeLinecap,'stroke-linejoin':style.strokeLinejoin,'stroke-dasharray':legacy?'1':style.strokeDasharray,'stroke-dashoffset':'0','fill':'none'}))paint.setAttribute(name,value);
  if(legacy)paint.setAttribute('pathLength','1');
  imageSvg.append(paint);
  const img=new Image();
  await new Promise((resolve,reject)=>{img.onload=resolve;img.onerror=()=>reject(Error('Could not rasterize the chart stroke'));img.src='data:image/svg+xml;charset=utf-8,'+encodeURIComponent(new XMLSerializer().serializeToString(imageSvg));});
  const canvas=document.createElement('canvas');canvas.width=Math.ceil(rect.width);canvas.height=Math.ceil(rect.height);
  const ctx=canvas.getContext('2d');ctx.drawImage(img,0,0);
  const length=path.getTotalLength(),samples=Array.from({length:25},(_,i)=>.02+i*.04);
  const painted=samples.map(f=>{
   const p=path.getPointAtLength(length*f),x=Math.round((p.x-box.x)/box.width*canvas.width),y=Math.round((p.y-box.y)/box.height*canvas.height);
   const left=Math.max(0,x-4),top=Math.max(0,y-4),width=Math.min(9,canvas.width-left),height=Math.min(9,canvas.height-top);
   const pixels=ctx.getImageData(left,top,width,height).data;
   for(let i=3;i<pixels.length;i+=4)if(pixels[i]>32)return true;
   return false;
  });
  const end=path.getPointAtLength(length),dot=svg.parentElement.querySelector('.chart-dot');
  return{width:rect.width,height:rect.height,samples:painted.length,painted:painted.filter(Boolean).length,tailPainted:painted.slice(-5).every(Boolean),dash:style.strokeDasharray,endpointX:end.x,viewBoxWidth:box.width,endDotLeft:dot.style.left,legacy};
 },legacy);
}
try{
 for(let i=0;i<40;i++){try{if((await fetch(base)).ok)break;}catch{}if(i===39)throw Error('App did not start');await new Promise(r=>setTimeout(r,500));}
 browser=await chromium.launch({executablePath:process.env.KICKX_BROWSER_EXECUTABLE||undefined});await mkdir(out,{recursive:true});
 for(const width of [1920,1440,768,390]){
  const now=Date.now(),assetHistory=values.map((value,i)=>({at:new Date(now-(values.length-1-i)*86400000).toISOString(),value}));
  const state={...emptyPlatformData(),session:{userId:'chart-member',role:'member',profile:{nickname:'그래프 확인'}},member:{financialReady:true,points:33767,totalAssets:1233000,playerAssets:1199233,returnRate:23.1,profit:0,realizedProfit:0,holdings:[],ownedPlayers:[],transactions:[],watchlist:[],assetHistory,squad:null}};
  const context=await browser.newContext({viewport:{width,height:1000},timezoneId:'Asia/Seoul'});
  await context.route(/^https:\/\//,route=>route.abort());
  await context.route('**/api/**',route=>{
   const path=new URL(route.request().url()).pathname;
   const ready=data=>route.fulfill({json:{status:'ready',source:'database',data}});
   if(path==='/api/kickx')return ready(state);
   if(path==='/api/kickx/notifications')return ready({hasUnread:false,matchNotifications:true});
   if(path==='/api/kickx/engagement')return ready({});
   return ready({items:[],total:0,page:1,size:20});
  });
  const page=await context.newPage();page.on('pageerror',e=>report.errors.push(e.message));
  await page.goto(base+'/portfolio',{waitUntil:'domcontentloaded'});
  const chart=page.locator('.pf-chart'),line=chart.locator('.chart-line');await line.waitFor();
  const month=await coverage(line);assert.equal(month.painted,month.samples,`Incomplete month stroke at ${width}: ${JSON.stringify(month)}`);assert(month.tailPainted);
  assert.equal(month.endpointX,month.viewBoxWidth);assert.equal(month.endDotLeft,'100%');
  const legacy=width===1920?await coverage(line,true):null;
  const pathBefore=await line.getAttribute('d');
  await chart.getByRole('button',{name:'1주',exact:true}).click();
  await page.waitForFunction(before=>document.querySelector('.pf-chart .chart-line')?.getAttribute('d')!==before,pathBefore);
  const week=await coverage(line);assert.equal(week.painted,week.samples,`Incomplete week stroke at ${width}`);assert(week.tailPainted);
  const plot=chart.locator('.chart-plot'),bounds=await plot.boundingBox();
  await plot.hover({position:{x:bounds.width-2,y:bounds.height/2}});
  assert.match(await chart.locator('.chart-tooltip strong').innerText(),/1,233,000/);
  await page.mouse.move(0,0);
  await chart.screenshot({path:`${out}/week-${width}.png`});
  await chart.getByRole('button',{name:'1개월',exact:true}).click();
  assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1));
  await chart.screenshot({path:`${out}/month-${width}.png`});
  report.layouts.push({viewport:width,month,week,legacy});
  await context.close();
 }
 assert.deepEqual(report.errors,[]);console.log(JSON.stringify(report));
}finally{await mkdir(out,{recursive:true});await writeFile(`${out}/report.json`,JSON.stringify(report,null,2));await browser?.close();server.kill('SIGTERM');}
