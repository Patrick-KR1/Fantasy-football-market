import {createClient} from '@supabase/supabase-js';
import {gzipSync,gunzipSync} from 'node:zlib';
import {createHash} from 'node:crypto';
import {mkdir,writeFile} from 'node:fs/promises';
import {nameImportFetch} from './lib/korean-catalog.mjs';
import {normalizeStatus} from './lib/football.mjs';
import {finalizeReference,observedMatchDuration} from './lib/report-reference';
import {calculatePerformance,regularSeasonScope} from '../server/kickx/engine/report-performance';
import type {ReportParameters} from '../server/kickx/engine/report-pricing';
type Ref=Parameters<typeof finalizeReference>[0]&{regularSeasonScopeVerified?:boolean;scopeAudit?:Record<string,unknown>};
const digest=(b:Uint8Array)=>createHash('sha256').update(b).digest('hex');
const checked=<T>(r:{data:T;error:unknown})=>{if(r.error)throw Error('SCOPE_DATABASE_RETRY');return r.data;};
async function main(){
 const key=process.env.SUPABASE_SERVICE_ROLE_KEY!;
 const db=createClient(process.env.SUPABASE_URL!,key,{global:{fetch:nameImportFetch(key)},auth:{persistSession:false,autoRefreshToken:false}});
 const policy=checked(await db.from('kickx_policy').select('version,report_reference,report_parameters,valuation_rebuild').single());
 if(!policy)throw Error('SCOPE_POLICY_REQUIRED');
 const original=policy.report_reference as Ref;if(original?.status!=='ready'){console.log(JSON.stringify({stage:'scope-reference',pending:'REFERENCE_NOT_READY'}));return;}
 if(original.regularSeasonScopeVerified){console.log(JSON.stringify({stage:'scope-reference',unchanged:true}));return;}
 const bucket=db.storage.from('kickx-calculation-archives');
 const before=gzipSync(Buffer.from(JSON.stringify(original)),{level:9}),beforeHash=digest(before),beforePath=`valuation-rebuild/20261001/reference-before-scope-${beforeHash}.json.gz`;
 const uploaded=await bucket.upload(beforePath,before,{contentType:'application/gzip',upsert:false});
 if(uploaded.error&&!['400','409'].includes(String(uploaded.error.statusCode)))throw Error('SCOPE_BACKUP_RETRY');
 const backup=checked(await bucket.download(beforePath));if(!backup||digest(Buffer.from(await backup.arrayBuffer()))!==beforeHash)throw Error('SCOPE_BACKUP_MISMATCH');
 const ref:Ref={...original,players:{},scores:{},archives:[],status:'collecting',completed:0,fixtureCount:0};
 const excluded:Record<string,unknown>[]=[];
 for(let at=0;at<original.archives.length;at+=8){
  const archives=original.archives.slice(at,at+8);
  const settled=await Promise.allSettled(archives.map(async a=>{
   const blob=checked(await bucket.download(a.path));if(!blob)throw Error('SCOPE_ARCHIVE_MISSING');
   const bytes=Buffer.from(await blob.arrayBuffer());if(digest(bytes)!==a.hash)throw Error('SCOPE_ARCHIVE_MISMATCH');
   const data=JSON.parse(gunzipSync(bytes).toString());
   if(data.format!=='kickx-report-reference-v1'||data.fixtureId!==a.fixtureId||data.detail.league_id!==a.league||data.detail.season_id!==original.leagues.find(l=>l.id===a.league)?.seasonId)throw Error('SCOPE_ARCHIVE_INVALID');
   const scope=regularSeasonScope(data.detail);if(scope===null){console.log(JSON.stringify({stage:'scope-unverified',fixtureId:a.fixtureId,league:a.league,matchStage:data.detail.stage,roundLabel:data.detail.round_label}));throw Error('SCOPE_STAGE_REQUIRED');}
   if(!scope)return {archive:a,excluded:{fixtureId:a.fixtureId,league:a.league,stage:data.detail.stage,date:data.detail.event_date,home:data.detail.home_team,away:data.detail.away_team},results:[]};
   const stats=data.stats.player_stats as {player_id:number;team_id:number;minutes_played:number}[];
   if(new Set(stats.map(s=>s.player_id)).size!==stats.length)throw Error('SCOPE_DUPLICATE_STATISTICS');
   const duration=observedMatchDuration(stats.map(s=>s.minutes_played),stats,data.incidents);
   return {archive:a,excluded:null,results:stats.map(s=>({playerId:`bsd-${s.player_id}`,...calculatePerformance({fixtureId:a.fixtureId,playerId:`bsd-${s.player_id}`,teamId:`bsd-${s.team_id}`,status:normalizeStatus(data.detail),homeTeam:`bsd-${data.detail.home_team_id}`,awayTeam:`bsd-${data.detail.away_team_id}`,homeScore:data.detail.home_score,awayScore:data.detail.away_score,stats:s,legacy:null,source:{detail:data.detail,lineups:data.lineups,incidents:data.incidents},durationMinutes:duration,regularSeasonOnly:true})}))};
  }));
  for(const result of settled){
   if(result.status==='rejected')throw result.reason;const data=result.value;
   if(data.excluded){excluded.push(data.excluded);continue;}
   ref.archives.push(data.archive);ref.completed++;ref.fixtureCount++;
   for(const r of data.results){if(r.score==null||!r.position||!['ready','provisional'].includes(r.status))continue;
    const player=ref.players[r.playerId]??={};const own=player[r.position]??={n:0,sum:0,fixtures:[]};own.n++;own.sum+=r.score;own.fixtures.push(data.archive.fixtureId);(ref.scores[r.position]??=[]).push(r.score);
   }
  }
  if(at%200===0)console.log(JSON.stringify({stage:'scope-reference',checked:Math.min(at+8,original.archives.length),regular:ref.completed,excluded:excluded.length}));
 }
 const ids=new Set(ref.archives.map(a=>Number(a.fixtureId.slice(4))));
 ref.leagues=ref.leagues.map(l=>({...l,fixtures:l.fixtures.filter(id=>ids.has(id))}));ref.leagueIndex=5;ref.fixtureIndex=0;
 finalizeReference(ref,policy.report_parameters as ReportParameters);ref.regularSeasonScopeVerified=true;
 ref.scopeAudit={checkedAt:new Date().toISOString(),previousHash:original.hash,sourceFixtureCount:original.fixtureCount,excluded,previousReferenceBackup:{path:beforePath,hash:beforeHash,bytes:before.length}};
 await mkdir('test-artifacts',{recursive:true});await writeFile('test-artifacts/scoped-reference.json.gz',gzipSync(Buffer.from(JSON.stringify(ref)),{level:9}));
 const summary={stage:'scope-reference-ready',regular:ref.fixtureCount,previous:original.fixtureCount,excluded,hash:ref.hash,leagues:ref.leagues.map(l=>({id:l.id,count:l.fixtures.length}))};
 await writeFile('test-artifacts/scope-summary.json',JSON.stringify(summary,null,2));console.log(JSON.stringify(summary));
 if(process.argv.includes('--apply')){
  const runtime=await fetch('https://kick-x-test.vercel.app/api/kickx',{method:'HEAD',signal:AbortSignal.timeout(10000),cache:'no-store'});
  if(!runtime.ok||runtime.headers.get('x-kickx-pricing-revision')!=='launch-dnp-regular-20261030')throw Error('SCOPE_DEPLOYMENT_REQUIRED');
  const applied=await db.rpc('kickx_replace_regular_reference',{p_expected_hash:original.hash,p_reference:ref});checked(applied);
  console.log(JSON.stringify({stage:'scope-reference-applied',...applied.data}));
 }
}
main().catch(e=>{console.error(JSON.stringify({error:e instanceof Error&&/^[A-Z_]+$/.test(e.message)?e.message:'SCOPE_REBUILD_RETRY'}));process.exitCode=1;});
