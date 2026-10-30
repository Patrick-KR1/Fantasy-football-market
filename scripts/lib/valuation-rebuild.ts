import {createHash} from 'node:crypto';
import {gzipSync} from 'node:zlib';
import {mkdir,writeFile} from 'node:fs/promises';
import type {SupabaseClient} from '@supabase/supabase-js';
import {createFootballClient,externalId,normalizeBatch,SyncError} from './football.mjs';
import {processBulkTask,BIG_FIVE} from './bulk-plan.mjs';
import {inspectValuationData} from './valuation-data-audit';

const checked=<T>(r:{data:T;error:unknown})=>{
 if(r.error){
  const code=(r.error as {code?:unknown}).code;
  throw new SyncError(`VALUATION_DATABASE_${typeof code==='string'&&/^[A-Z0-9]{5}$/.test(code)?code:'RETRY'}`);
 }
 return r.data;
};
const hash=(v:Uint8Array)=>createHash('sha256').update(v).digest('hex');
async function seedNonParticipation(db:SupabaseClient){
 let seeded=0;
 for(let batch=0;batch<500;batch++){
  const work=checked(await db.rpc('kickx_non_participation_work'));
  seeded+=work.inserted;
  if(work.remaining===0)return seeded;
 }
 throw new SyncError('VALUATION_NON_PARTICIPATION_RETRY');
}
async function all(db:SupabaseClient,table:string,select='*'){
 const rows:Record<string,unknown>[]=[];
 for(let at=0;;at+=500){
  const key=table==='football_entity_sources'?'kind':table==='football_event_sources'?'fixture_id':['football_match_stats','performance_results','player_price_results','player_initial_values','player_match_records'].includes(table)?'player_id':'id';
  let query=db.from(table).select(select).order(key);
  if(table==='football_entity_sources')query=query.eq('kind','squad');
  if(['football_match_stats','performance_results','player_price_results','player_match_records'].includes(table))query=query.order('fixture_id');
  if(table==='football_entity_sources')query=query.order('external_id');
  const q=await query.range(at,at+499);checked(q);
  rows.push(...q.data as unknown as Record<string,unknown>[]);if((q.data?.length??0)<500)return rows;
 }
}
export async function ensureValuationRebuild(db:SupabaseClient,key:string,{emit=(v:unknown)=>{void v;}}={}){
 const response=await db.from('kickx_policy').select('valuation_rebuild').single();
 if(response.error&&['42703','PGRST204'].includes(response.error.code))return {pending:'VALUATION_MIGRATION_REQUIRED'};
 const state=checked(response)?.valuation_rebuild;
 if(['validated','active'].includes(state?.status))return {status:state.status,seeded:await seedNonParticipation(db)};
 const now=new Date().toISOString(),leagues:Record<string,unknown>[]=[],teamIds=new Set<string>(),fixtureIds=new Set<string>();
 const api=createFootballClient({key,budget:1000,delay:80,timeoutMs:12000,fetchImpl:async(...args:Parameters<typeof fetch>)=>{
  const budget=checked(await db.from('football_bulk_daily_budget').select('requests').eq('day',new Date().toISOString().slice(0,10)).maybeSingle());
  if((budget?.requests??0)>=5500)throw new SyncError('VALUATION_LIVE_RESERVE');
  const reservation=await db.rpc('kickx_reserve_provider_request');if(reservation.error)throw new SyncError('VALUATION_REQUEST_RESERVATION_FAILED');return fetch(...args);
 }});
 const apply=async(outcome:unknown)=>checked(await db.rpc('kickx_apply_automatic_task',{p_outcome:outcome}));
 let squadPlayers=0;
 for(const league of BIG_FIVE){
  const current=await api.get(`/api/v2/leagues/${league.id}/season/`),season=current.season;
  if(!season?.is_current||current.league_id!==league.id)throw new Error('VALUATION_SEASON_MISMATCH');
  const context={league:league.id,seasonId:season.id,seasonYear:season.year,leagueName:league.name};
  const seen:number[]=[];let offset:number|null=0;
  do{
   const page=await api.page('/api/v2/teams/',{league_id:league.id,season_id:season.id,limit:200,offset});
   seen.push(...page.results.map((t:{id:number})=>t.id));await apply({batch:normalizeBatch('teams',page.results,context)});offset=page.next;
  }while(offset!=null);
  if(new Set(seen).size!==([5,6].includes(league.id)?18:20))throw new Error('VALUATION_TEAM_COUNT_MISMATCH');
  for(const id of seen){
   teamIds.add(externalId(id));const outcome=await processBulkTask(api,{kind:'squad',payload:{context,teamId:id}},now.slice(0,10)) as unknown as {batch:{players:unknown[]}|null};
   if(!outcome.batch)throw new Error('VALUATION_SQUAD_EMPTY');
   squadPlayers+=outcome.batch.players.length;await apply(outcome);
  }
  await apply({leagueMembership:{leagueId:externalId(league.id),teamIds:seen.map(externalId)}});
  let fixtures=0,finished=0;offset=0;
  do{
   const page=await api.page('/api/v2/events/',{league_id:league.id,season_id:season.id,limit:200,offset});
   await apply({batch:normalizeBatch('fixtures',page.results,context)});
   for(const fixture of page.results){const id=externalId(fixture.id);if(fixtureIds.has(id))throw new Error('VALUATION_DUPLICATE_FIXTURE');fixtureIds.add(id);fixtures++;if(fixture.status==='finished')finished++;}
   offset=page.next;
  }while(offset!=null);
  if(fixtures<seen.length*(seen.length-1))throw new Error('VALUATION_SCHEDULE_INCOMPLETE');
  leagues.push({leagueId:externalId(league.id),season:season.year,providerSeasonId:season.id,teams:seen.length,fixtures,finished});
  emit({stage:'valuation-catalog',league:league.id,teams:seen.length,fixtures,requests:api.requests});
 }
 const [players,fixtures,stats,sources,squads]=await Promise.all([
  all(db,'players','id,team_id,position,name,name_ko'),all(db,'fixtures','id,league_id,season,status,home_team_id,away_team_id,provider_season_id,home_score,away_score'),
  all(db,'football_match_stats','fixture_id,player_id,minutes:stats->minutes_played'),all(db,'football_event_sources','fixture_id,lineups,incidents'),all(db,'football_entity_sources','kind,external_id,raw')
 ]);
 const playerById=new Map(players.map(p=>[p.id,p])),dbFixtures=new Set(fixtures.map(f=>String(f.id))),statFixtures=new Set(stats.map(s=>s.fixture_id)),sourceFixtures=new Set(sources.map(s=>s.fixture_id));
 const missingFixtures=[...fixtureIds].filter(id=>!dbFixtures.has(id)),missingPlayers:string[]=[];
 for(const squad of squads.filter(s=>s.kind==='squad'&&teamIds.has(externalId(Number(s.external_id))))){
  for(const player of (squad.raw as {players:{id:number}[]}).players){
   const id=externalId(player.id),row=playerById.get(id);if(!row||row.team_id!==externalId(Number(squad.external_id)))missingPlayers.push(id);
  }
 }
 const qualityBefore=inspectValuationData({players,fixtures,statistics:stats,sources,currentTeamIds:teamIds});
 emit({stage:'valuation-quality',...qualityBefore});
 const repairIds=new Set((qualityBefore?.repairFixtures??[]) as string[]);
 const missingStats=fixtures.filter(f=>fixtureIds.has(String(f.id))&&f.status==='FT'&&(!statFixtures.has(f.id)||!sourceFixtures.has(f.id)||repairIds.has(String(f.id))));
 for(const fixture of missingStats){
  const league=leagues.find(l=>l.leagueId===fixture.league_id)!;
  const context={league:Number(String(fixture.league_id).slice(4)),seasonId:Number(fixture.provider_season_id),seasonYear:Number(league.season)};
  let task={kind:'match',payload:{context,eventId:Number(String(fixture.id).slice(4)),phase:'detail'}};
  for(let phase=0;phase<100;phase++){
   const outcome=await processBulkTask(api,task,now.slice(0,10)) as unknown as {done:boolean;batch:unknown;entities?:unknown;payload:typeof task.payload};if(outcome.batch||outcome.entities)await apply(outcome);
   if(outcome.done)break;task={...task,payload:outcome.payload};if(phase===99)throw new Error('VALUATION_REPAIR_INCOMPLETE');
  }
 }
 if(missingFixtures.length||missingPlayers.length)throw new Error('VALUATION_CATALOG_INCOMPLETE');
 const [finalStatistics,finalSources,finalFixtures]=missingStats.length?await Promise.all([
  all(db,'football_match_stats','fixture_id,player_id,minutes:stats->minutes_played'),all(db,'football_event_sources','fixture_id,lineups,incidents'),
  all(db,'fixtures','id,league_id,season,status,home_team_id,away_team_id,provider_season_id,home_score,away_score')
 ]):[stats,sources,fixtures];
 const finalStats=new Set(finalStatistics.map(s=>s.fixture_id));
 if(finalFixtures.some(f=>fixtureIds.has(String(f.id))&&f.status==='FT'&&!finalStats.has(f.id)))throw new Error('VALUATION_STATISTICS_INCOMPLETE');
 const audit={complete:true,checkedAt:now,leagues,teams:teamIds.size,squadPlayers,fixtures:fixtureIds.size,
  missingPlayers:missingPlayers.length,missingFixtures:missingFixtures.length,repairedMatches:missingStats.length,
  unknownFixtures:finalFixtures.filter(f=>fixtureIds.has(String(f.id))&&['UNKNOWN','UNRESOLVED'].includes(String(f.status))).map(f=>f.id),
  dataQuality:inspectValuationData({players,fixtures:finalFixtures,statistics:finalStatistics,sources:finalSources,currentTeamIds:teamIds}),
  historicalRosterLimitation:'Unlisted historical squad members are not inferred from the current roster.'};
 const datasets:Record<string,unknown>={};
 for(const [table,columns]of [
  ['performance_results','*'],['player_initial_values','*'],['player_price_results','*'],['price_history','*'],
  ['player_market_snapshots','*'],['player_match_records','player_id,fixture_id,performance,rule_version'],['ranking_snapshots','*'],['asset_snapshots','*']
 ]){
  const rows=await all(db,table,columns);datasets[table]=rows;
  emit({stage:'valuation-backup-read',table,rows:rows.length});
 }
 const integrity=checked(await db.rpc('kickx_valuation_integrity'));
 const bytes=gzipSync(Buffer.from(JSON.stringify({format:'kickx-valuation-backup-v1',asOf:new Date().toISOString(),audit,integrity,datasets})),{level:9});
 const digest=hash(bytes),path=`valuation-rebuild/20261001/before-${digest}.json.gz`;
 const bucketMetadata=checked(await db.storage.getBucket('kickx-calculation-archives'));if(!bucketMetadata||bucketMetadata.public)throw new Error('VALUATION_BACKUP_NOT_PRIVATE');
 const bucket=db.storage.from('kickx-calculation-archives');
 const uploaded=await bucket.upload(path,bytes,{contentType:'application/gzip',upsert:false});
 if(uploaded.error&&!['400','409'].includes(String(uploaded.error.statusCode)))throw new Error('VALUATION_BACKUP_RETRY');
 const restored=checked(await bucket.download(path));if(!restored||hash(Buffer.from(await restored.arrayBuffer()))!==digest)throw new Error('VALUATION_BACKUP_MISMATCH');
 checked(await db.rpc('kickx_stage_valuation_rebuild',{p_manifest:{status:'validated',audit,backup:{path,hash:digest,bytes:bytes.length},integrity}}));
 const seeded=await seedNonParticipation(db);
 await mkdir('test-artifacts',{recursive:true});await writeFile('test-artifacts/valuation-audit.json',JSON.stringify({...audit,backupBytes:bytes.length,seeded},null,2));
 emit({stage:'valuation-audit',...audit,backupBytes:bytes.length,seeded,requests:api.requests});return {status:'validated',seeded};
}

