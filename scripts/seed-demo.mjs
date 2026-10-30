import {createClient} from '@supabase/supabase-js';
import {createHash} from 'node:crypto';
import {readFile,mkdir,writeFile} from 'node:fs/promises';
import {nameImportFetch} from './lib/korean-catalog.mjs';
import {buildDemoData,SAMPLE_BATCH,sampleId} from './lib/demo-content.mjs';
const checked=r=>{if(r.error){const code=/^[A-Z0-9_]+$/.test(r.error.message??'')?r.error.message:/^[A-Z0-9_]+$/.test(r.error.code??'')?r.error.code:'RETRY';throw Error(`SAMPLE_${code}`);}return r.data;};
const hash=v=>createHash('sha256').update(JSON.stringify(v)).digest('hex');
async function all(db,table,ids){
 const out=[];for(let at=0;at<20000;at+=500){
  let q=db.from(table).select('*').order(table==='trades'?'sequence':table==='holdings'?'user_id':table==='profiles'?'id':'user_id');
  if(table==='holdings')q=q.order('player_id');if(ids)q=q.in(table==='profiles'?'id':'user_id',ids);
  const data=checked(await q.range(at,at+499));out.push(...data);if(data.length<500)return out;
 }throw Error('SAMPLE_READ_LIMIT');
}
async function financial(db,ids){return Object.fromEntries(await Promise.all(['wallets','trades','holdings'].map(async t=>[t,hash(ids.length?await all(db,t,ids):[])])));}
async function main(){
 const source=JSON.parse(await readFile('data/demo/source-20261030.json','utf8')),plan=buildDemoData(source);
 await mkdir('test-artifacts',{recursive:true});
 if(!process.argv.includes('--apply')){await writeFile('test-artifacts/demo-preview.json',JSON.stringify(plan,null,2));console.log(JSON.stringify({preview:true,users:plan.users.length,posts:plan.posts.length,comments:plan.comments.length}));return;}
 const key=process.env.SUPABASE_SERVICE_ROLE_KEY;
 const db=createClient(process.env.SUPABASE_URL,key,{global:{fetch:nameImportFetch(key)},auth:{persistSession:false,autoRefreshToken:false}});
 const policy=checked(await db.from('kickx_policy').select('initial_points,sell_fee_bps,report_parameters').single());
 if(policy.initial_points!==1_300_000||policy.sell_fee_bps!==200||policy.report_parameters.initialMin!==50000||policy.report_parameters.initialMax!==150000)throw Error('SAMPLE_POLICY_CHANGED');
 const original=checked(await db.from('profiles').select('id').or(`sample_batch.is.null,sample_batch.neq.${SAMPLE_BATCH}`)).map(p=>p.id);
 const before=await financial(db,original),created=[];
 const action=async(u,kind,input={})=>{
  for(let attempt=0;attempt<8;attempt++){
   const r=await db.rpc('kickx_sample_action',{p_user:u,p_action:kind,p_input:input});
   if(r.error?.message==='TOO_FAST'){await new Promise(resolve=>setTimeout(resolve,500));continue;}
   return checked(r);
  }throw Error('SAMPLE_COOLDOWN_RETRY');
 };
 for(const u of plan.users){
  let r=await db.auth.admin.getUserById(u.id);
  if(r.error&&r.error.status!==404&&r.error.code!=='user_not_found')throw Error('SAMPLE_AUTH_LOOKUP');
  if(!r.data?.user){
   r=await db.auth.admin.createUser({id:u.id,email:u.email,email_confirm:true,ban_duration:'876000h',app_metadata:{kickx_sample_batch:SAMPLE_BATCH},user_metadata:{nickname:u.nickname}});
   if(r.error)throw Error(`SAMPLE_AUTH_${r.error.code??'CREATE'}`);created.push(u.id);
  }
  if(r.data.user.app_metadata?.kickx_sample_batch!==SAMPLE_BATCH||!r.data.user.banned_until||Date.parse(r.data.user.banned_until)<=Date.now())throw Error('SAMPLE_AUTH_MARKER_REQUIRED');
  checked(await db.from('profiles').upsert({id:u.id,nickname:u.nickname,team_id:u.primaryTeam,team_ids:u.teams,sample_batch:SAMPLE_BATCH},{onConflict:'id'}));
  await action(u.id,'open');
  const result=await action(u.id,'portfolio',{trades:u.trades});
  u.actualTrades=result.trades;
  console.log(JSON.stringify({stage:'sample-account',index:u.index+1,trades:result.trades.length,skipped:result.skipped}));
 }
 const watch=new Map();
 const saveWatch=(user,player)=>watch.set(`${user}:${player}`,{user_id:user,player_id:player});
 for(const u of plan.users)for(const t of u.trades.filter(t=>t.side==='buy').slice(0,4))saveWatch(u.id,t.playerId);
 for(const c of plan.comments){const p=plan.posts.find(p=>p.key===c.postKey);if(p.scope==='player')saveWatch(plan.users[c.author].id,p.target);}
 checked(await db.from('watchlists').upsert([...watch.values()],{onConflict:'user_id,player_id'}));
 const ids=new Map(),comments=new Map();
 // Two passes leave the ordinary three-second posting cooldown intact.
 for(const scope of ['player','club'])for(const p of plan.posts.filter(p=>p.scope===scope)){
  const u=plan.users[p.author],trade=p.tradeRequest?u.actualTrades.find(t=>t.request_id===p.tradeRequest):null;
  const r=await action(u.id,'post',{requestId:sampleId(p.key),scope:p.scope,target:p.target,title:p.title,body:p.body,transaction:trade?.id??''});ids.set(p.key,r.id);
 }
 for(const c of plan.comments){
  const result=await action(plan.users[c.author].id,'comment',{postId:ids.get(c.postKey),requestId:sampleId(c.key),body:c.body,parentId:c.parentKey?comments.get(c.parentKey):null});comments.set(c.key,result.id);
 }
 const after=await financial(db,original);if(hash(before)!==hash(after))throw Error('SAMPLE_EXISTING_FINANCE_CHANGED');
 const userIds=plan.users.map(u=>u.id),wallets=await all(db,'wallets',userIds),holdings=await all(db,'holdings',userIds),trades=await all(db,'trades',userIds);
 const result={batch:SAMPLE_BATCH,completedAt:new Date().toISOString(),sourceAsOf:source.asOf,users:50,newAuthUsers:created.length,trades:trades.length,holdings:holdings.length,posts:ids.size,comments:comments.size,attachments:plan.posts.filter(p=>p.tradeRequest&&plan.users[p.author].actualTrades.some(t=>t.request_id===p.tradeRequest)).length,initialPoints:wallets[0]?.initial_points,existingUserCount:original.length,existingFinanceUnchanged:true,financialFingerprints:{before,after},userIds};
 await writeFile('test-artifacts/demo-seed-result.json',JSON.stringify(result,null,2));
 console.log(JSON.stringify({stage:'sample-complete',...result}));
}
main().catch(e=>{console.error(/^[A-Z0-9_]+$/.test(e.message??'')?e.message:'SAMPLE_RETRY');process.exitCode=1;});
