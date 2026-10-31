import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {buildDemoData,SAMPLE_BATCH} from '../scripts/lib/demo-content.mjs';
const source=JSON.parse(readFileSync(new URL('../data/demo/source-20261030.json',import.meta.url),'utf8'));
const plan=buildDemoData(source),byId=new Map(source.players.map(p=>[p.id,p]));
test('50 marked accounts have consistent affordable trades and no duplicate holdings',()=>{
 assert.equal(plan.batch,SAMPLE_BATCH);assert.equal(plan.users.length,50);assert.equal(new Set(plan.users.map(u=>u.id)).size,50);
 assert.equal(new Set(plan.users.map(u=>u.nickname)).size,50);
 for(const u of plan.users){
  assert.ok(!u.nickname.includes('샘플')&&u.nickname.length>=2&&u.nickname.length<=20);assert.ok(u.email.endsWith('@example.invalid'));
  assert.equal(new Set(u.teams.map(id=>source.clubs.find(t=>t.id===id).league)).size,u.teams.length);
  let cash=1_300_000;const owned=new Set();
  for(const t of u.trades){const price=byId.get(t.playerId).price;
   if(t.side==='buy'){assert.ok(!owned.has(t.playerId));owned.add(t.playerId);cash-=price;}
   else{assert.ok(owned.has(t.playerId));owned.delete(t.playerId);cash+=price-Math.round(price*.02);}
   assert.ok(cash>=0);
  }
  assert.ok(owned.size>=3&&owned.size<=10);assert.ok(cash>=100000);
 }
});
test('post attachments belong to authors and every statement cites a collected fixture',()=>{
 assert.equal(plan.posts.length,100);assert.equal(new Set(plan.posts.map(p=>p.title)).size,100);
 for(const p of plan.posts){
  const u=plan.users[p.author],anchor=byId.get(u.anchor);
  assert.ok(anchor.recent.some(r=>r.fixture_id===p.sourceFixture));assert.ok(p.body.includes(anchor.name_ko)||p.title.includes(anchor.name_ko));
  if(p.scope==='club')assert.ok(u.teams.includes(p.target));else assert.equal(p.target,u.anchor);
  if(p.tradeRequest)assert.ok(u.trades.some(t=>t.requestId===p.tradeRequest));
  assert.ok(p.title.length>=2&&p.title.length<=80&&p.body.length>=10&&p.body.length<=3000);
 }
 assert.ok(plan.posts.filter(p=>p.tradeRequest).length>=30);
});
test('discussion respects club membership and replies remain on the same post',()=>{
 assert.equal(plan.comments.length,120);
 for(const c of plan.comments){const p=plan.posts.find(p=>p.key===c.postKey),u=plan.users[c.author];
  if(p.scope==='club')assert.ok(u.teams.includes(p.target));
  if(c.parentKey)assert.equal(plan.comments.find(a=>a.key===c.parentKey).postKey,c.postKey);
  else assert.notEqual(c.author,p.author);
 }
 assert.deepEqual(buildDemoData(source),plan);
});
