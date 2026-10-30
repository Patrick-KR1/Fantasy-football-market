import {createClient} from '@supabase/supabase-js';
import {createHash} from 'node:crypto';
import {gzipSync} from 'node:zlib';
import {mkdir,writeFile} from 'node:fs/promises';
import {nameImportFetch} from './lib/korean-catalog.mjs';
const RESET='launch-20261015-initial50k150k';
const checked=r=>{if(r.error)throw Error(`RESET_DATABASE_${/^[A-Z0-9]+$/.test(r.error.code??'')?r.error.code:'RETRY'}`);return r.data;};
const digest=b=>createHash('sha256').update(b).digest('hex');
async function rows(db,table){
 const out=[];
 for(let at=0;at<100000;at+=500){
  let q=db.from(table).select('*').order(['player_initial_values','player_price_results','player_calculation_state'].includes(table)?'player_id':'id');
  if(table==='player_price_results')q=q.order('fixture_id');
  const data=checked(await q.range(at,at+499));out.push(...data);if(data.length<500)return out;
 }
 throw Error('RESET_BACKUP_TOO_LARGE');
}
async function main(){
 if(!process.argv.includes('--apply'))throw Error('RESET_APPLY_REQUIRED');
 const key=process.env.SUPABASE_SERVICE_ROLE_KEY;
 const db=createClient(process.env.SUPABASE_URL,key,{global:{fetch:nameImportFetch(key)},auth:{persistSession:false,autoRefreshToken:false}});
 const before=checked(await db.rpc('kickx_valuation_integrity'));
 const policy=checked(await db.from('kickx_policy').select('version,report_parameters,report_reference,pricing_reference_at,pricing_reference_season,valuation_rebuild').single());
 let manifest=policy.valuation_rebuild?.priceReset?.backup;
 if(policy.valuation_rebuild?.priceReset?.id!==RESET){
  const tables=['player_market_snapshots','player_initial_values','player_price_results','price_history','player_calculation_state','asset_snapshots','ranking_snapshots'];
  const datasets=Object.fromEntries(await Promise.all(tables.map(async t=>[t,await rows(db,t)])));
  const bytes=gzipSync(Buffer.from(JSON.stringify({format:'kickx-approved-price-reset-v1',checkedAt:new Date().toISOString(),policy,integrity:before,datasets})),{level:9});
  const hash=digest(bytes),path=`valuation-rebuild/20261015/before-${hash}.json.gz`;
  const bucketMetadata=checked(await db.storage.getBucket('kickx-calculation-archives'));
  if(bucketMetadata.public)throw Error('RESET_PRIVATE_BACKUP_REQUIRED');
  const bucket=db.storage.from('kickx-calculation-archives');
  const uploaded=await bucket.upload(path,bytes,{contentType:'application/gzip',upsert:false});
  if(uploaded.error&&!['400','409'].includes(String(uploaded.error.statusCode)))throw Error('RESET_BACKUP_RETRY');
  const restored=checked(await bucket.download(path));
  if(digest(Buffer.from(await restored.arrayBuffer()))!==hash)throw Error('RESET_BACKUP_MISMATCH');
  manifest={path,hash,bytes:bytes.length,integrity:before};
  console.log(JSON.stringify({stage:'approved-reset-backup',bytes:bytes.length,hash,rows:Object.fromEntries(tables.map(t=>[t,datasets[t].length]))}));
  const reference={...policy.report_reference,scopeAudit:{...policy.report_reference.scopeAudit,priceReset:{id:RESET,backup:manifest,initialMin:50000,initialMax:150000,startsAt:'2026-10-14T15:00:00Z'}}};
  delete reference.hash;reference.hash=digest(Buffer.from(JSON.stringify(reference)));
  const reset=checked(await db.rpc('kickx_reset_october15_prices',{p_expected_parameters:policy.report_parameters,p_backup:manifest,p_reference:reference}));
  console.log(JSON.stringify({stage:'approved-reset-applied',...reset}));
 }
 let processed=0,withheld=0;
 for(let batch=0;batch<500;batch++){
  const result=checked(await db.rpc('kickx_replay_cached_prices',{p_limit:15}));
  processed+=result.processed;withheld+=result.withheld;
  if(batch%20===0||result.remaining===0)console.log(JSON.stringify({stage:'approved-reset-replay',processed,withheld,remaining:result.remaining}));
  if(result.remaining===0)break;
  if(result.processed===0){
   const calculatorModule=await import('../server/kickx/engine/service.ts');
   const calculatePlayer=calculatorModule.calculatePlayer??calculatorModule.default?.calculatePlayer;
   if(typeof calculatePlayer!=='function')throw Error('RESET_CALCULATOR_REQUIRED');
   const pending=checked(await db.from('calculation_queue').select('player_id,revision').is('error_code',null).order('queued_at').limit(60));
   if(!pending.length)throw Error('RESET_QUEUE_CHANGED');
   for(let at=0;at<pending.length;at+=3)await Promise.all(pending.slice(at,at+3).map(async q=>{
    const answer=await calculatePlayer(db,q.player_id,null);
    checked(await db.rpc('kickx_ack_calculation',{p_player:q.player_id,p_revision:q.revision,p_error:answer.withheld?'CALCULATION_WITHHELD':null}));
   }));
  }
  if(batch===499)throw Error('RESET_REPLAY_LIMIT');
 }
 const portfolios=checked(await db.rpc('kickx_finish_valuation_rebuild'));
 const after=checked(await db.rpc('kickx_valuation_integrity'));
 if(JSON.stringify(before)!==JSON.stringify(after))throw Error('RESET_FINANCIAL_INTEGRITY');
 const outcome={checkedAt:new Date().toISOString(),resetId:RESET,startsAt:'2026-10-14T15:00:00Z',initialMin:50000,initialMax:150000,processed,withheld,portfolios,backup:manifest,financialIntegrityUnchanged:true,providerRequests:0};
 await mkdir('test-artifacts',{recursive:true});await writeFile('test-artifacts/approved-price-reset.json',JSON.stringify(outcome,null,2));
 console.log(JSON.stringify({stage:'approved-reset-complete',...outcome}));
}
main().catch(e=>{console.error(/^[A-Z0-9_]+$/.test(e.message??'')?e.message:'RESET_RETRY');process.exitCode=1;});
