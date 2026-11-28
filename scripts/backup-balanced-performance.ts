import {loadEnvConfig} from '@next/env';
import {createClient} from '@supabase/supabase-js';
import {createHash} from 'node:crypto';
import {gzipSync} from 'node:zlib';
import {mkdir,writeFile} from 'node:fs/promises';
import {nameImportFetch} from './lib/korean-catalog.mjs';
import {calculatePlayer} from '../server/kickx/engine/service';
import {SCORING_REVISION} from '../server/kickx/engine/report-policy';

loadEnvConfig(process.cwd());
const checked=<T>(r:{data:T;error:unknown}):NonNullable<T>=>{if(r.error||r.data==null)throw Error('BALANCED_DATABASE_RETRY');return r.data;};
const digest=(bytes:Buffer)=>createHash('sha256').update(bytes).digest('hex');
async function main(){
 const url=process.env.SUPABASE_URL,key=process.env.SUPABASE_SERVICE_ROLE_KEY?.trim();
 if(!url||new URL(url).protocol!=='https:'||!key)throw Error('BALANCED_CONFIG_REQUIRED');
 const db=createClient(url,key,{global:{fetch:nameImportFetch(key)},auth:{persistSession:false,autoRefreshToken:false}});
 // This uses the policy-selected scorer: an old active policy is repaired with
 // the old rules. No provider calls, resets or forced incomplete publications.
 const stale=checked(await db.rpc('kickx_balanced_stale_players')) as string[];
 let withheld=0;
 for(let at=0;at<stale.length;at+=3){
  await Promise.all(stale.slice(at,at+3).map(async id=>{
   const result=await calculatePlayer(db,id,null);
   if(result.withheld)withheld++;
  }));
 }
 console.log(JSON.stringify({stage:'balanced-base-evidence',players:stale.length,withheld}));
 const state=checked(await db.rpc('kickx_balanced_replay_state'));
 const policy=checked(await db.from('kickx_policy').select('version,report_parameters,report_reference,pricing_reference_at,pricing_reference_season').single());
 const specs:Array<[string,string[],string?]>=[
  ['performance_results',['player_id','fixture_id']],['player_initial_values',['player_id']],
  ['player_price_results',['player_id','fixture_id']],['price_history',['player_id','recorded_at']],
  ['player_market_snapshots',['id']],['player_match_records',['player_id','fixture_id'],'player_id,fixture_id,performance,rule_version'],
  ['calculation_revisions',['player_id','created_at','id']],['player_calculation_state',['player_id']],
  ['asset_snapshots',['id']],['ranking_snapshots',['id']],
 ];
 const datasets:Record<string,unknown[]>={};
 for(const [table,order,columns]of specs){
  const rows:unknown[]=[];
  for(let offset=0;offset<200000;offset+=500){
   let query=db.from(table).select(columns??'*');
   if(table==='calculation_revisions')query=query.eq('rule_version','report-v3').is('archive_path',null);
   for(const column of order)query=query.order(column);
   const page=checked(await query.range(offset,offset+499));rows.push(...page);
   if(page.length<500)break;
   if(offset===199500)throw Error('BALANCED_BACKUP_LIMIT');
  }
  datasets[table]=rows;
 }
 if(JSON.stringify(state)!==JSON.stringify(checked(await db.rpc('kickx_balanced_replay_state'))))throw Error('BALANCED_SOURCE_CHANGED');
 const bytes=gzipSync(Buffer.from(JSON.stringify({format:'kickx-balanced-performance-v1',revision:SCORING_REVISION,checkedAt:new Date().toISOString(),state,policy,datasets})),{level:9});
 if(bytes.length>20*1024*1024)throw Error('BALANCED_BACKUP_LIMIT');
 const bucketId='kickx-calculation-archives';
 if(checked(await db.storage.getBucket(bucketId)).public!==false)throw Error('BALANCED_PRIVATE_BACKUP_REQUIRED');
 const hash=digest(bytes),path=`performance-rebalance/${SCORING_REVISION}/${hash}.json.gz`,bucket=db.storage.from(bucketId);
 const upload=await bucket.upload(path,bytes,{contentType:'application/gzip',upsert:false});
 if(upload.error&&!['400','409'].includes(String(upload.error.statusCode)))throw Error('BALANCED_UPLOAD_RETRY');
 const restored=checked(await bucket.download(path));
 if(digest(Buffer.from(await restored.arrayBuffer()))!==hash)throw Error('BALANCED_BACKUP_MISMATCH');
 if(JSON.stringify(state)!==JSON.stringify(checked(await db.rpc('kickx_balanced_replay_state'))))throw Error('BALANCED_SOURCE_CHANGED');
 const manifest={stage:'balanced-backup-verified',revision:SCORING_REVISION,path,hash,bytes:bytes.length,state,rowCounts:Object.fromEntries(Object.entries(datasets).map(([table,rows])=>[table,rows.length]))};
 await mkdir('test-artifacts',{recursive:true});
 await writeFile('test-artifacts/balanced-performance-backup.json',JSON.stringify(manifest,null,2));
 console.log(JSON.stringify(manifest));
}
main().catch(error=>{console.error(/^[A-Z0-9_]+$/.test(error.message??'')?error.message:'BALANCED_RETRY');process.exitCode=1;});
