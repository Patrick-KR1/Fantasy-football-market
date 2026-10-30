/** Inventory audit: no football, price, wallet or policy writes.
 * The existing shared provider request counter is reserved for each external call. */
import {loadEnvConfig} from '@next/env';
import {createClient} from '@supabase/supabase-js';
import {gunzipSync} from 'node:zlib';
import {mkdir,writeFile} from 'node:fs/promises';
import {createFootballClient,externalId,SyncError} from './lib/football.mjs';
import {nameImportFetch} from './lib/korean-catalog.mjs';
import {calculatePerformance} from '../server/kickx/engine/report-performance';
import {observedMatchDuration} from './lib/report-reference';

loadEnvConfig(process.cwd());
async function main(){
 const url=process.env.SUPABASE_URL,key=process.env.SUPABASE_SERVICE_ROLE_KEY,bsd=process.env.BSD_API_KEY;
 if(!url||!key||!bsd)throw new Error('AUDIT_CONFIG_REQUIRED');
 const db=createClient(url,key,{global:{fetch:nameImportFetch(key)},auth:{persistSession:false,autoRefreshToken:false}});
 const checked=<T>(r:{data:T;error:unknown})=>{if(r.error)throw new Error('AUDIT_DATABASE_ERROR');return r.data;};
 const rows=async(table:string,select:string,order:string)=>{
  const out:Record<string,unknown>[]=[];
  for(let offset=0;;offset+=500){
   let q=db.from(table).select(select).order(order);
   if(table==='football_match_stats')q=q.order('fixture_id');
   const r=await q.range(offset,offset+499);checked(r);out.push(...r.data as unknown as Record<string,unknown>[]);
   if((r.data?.length??0)<500)return out;
  }
 };
 const [players,teams,fixtures,statistics,sources,policy]=await Promise.all([
  rows('players','id,team_id,position,name_ko','id'),rows('teams','id,league_id','id'),
  rows('fixtures','id,league_id,provider_season_id,season,status,home_score,away_score','id'),
  rows('football_match_stats','player_id,fixture_id,minutes:stats->minutes_played','player_id'),
  rows('football_event_sources','fixture_id,lineups,incidents','fixture_id'),
  db.from('kickx_policy').select('version,report_reference').single()
 ]);
 checked(policy);
 const api=createFootballClient({key:bsd,budget:180,delay:80,timeoutMs:10000,fetchImpl:async(...args:Parameters<typeof fetch>)=>{
  checked(await db.rpc('kickx_reserve_provider_request'));return fetch(...args);
 }});
 const byPlayer=new Map(players.map(p=>[p.id,p])),byTeam=new Map(teams.map(t=>[t.id,t])),byFixture=new Map(fixtures.map(f=>[f.id,f]));
 const reports=[];const allTeams=new Set<string>(),allPlayers=new Set<string>(),allFixtures=new Set<string>();
 for(const league of [1,3,4,5,6]){
  const current=await api.get(`/api/v2/leagues/${league}/season/`),season=current.season;
  if(current.league_id!==league||!season?.is_current)throw new Error('AUDIT_SEASON_MISMATCH');
  const clubIds:number[]=[];let offset:number|null=0;
  do{const p=await api.page('/api/v2/teams/',{league_id:league,season_id:season.id,limit:200,offset});clubIds.push(...p.results.map((t:{id:number})=>t.id));offset=p.next;}while(offset!=null);
  const missingTeams:string[]=[],missingPlayers:string[]=[],wrongMembership:string[]=[],missingFixtures:string[]=[],statusDifferences:Record<string,unknown>[]=[];
  let members=0,matches=0;
  for(const id of clubIds){
   const tid=externalId(id);allTeams.add(tid);if(!byTeam.has(tid))missingTeams.push(tid);
   const squad=await api.get(`/api/v2/teams/${id}/squad/`);
   if(squad.team_id!==id||squad.count!==squad.players?.length)throw new Error('AUDIT_SQUAD_MISMATCH');
   for(const member of squad.players){
    const pid=externalId(member.id);allPlayers.add(pid);members++;
    const stored=byPlayer.get(pid);if(!stored)missingPlayers.push(pid);else if(stored.team_id!==tid)wrongMembership.push(pid);
   }
  }
  offset=0;
  do{
   const p=await api.page('/api/v2/events/',{league_id:league,season_id:season.id,limit:200,offset});
   for(const f of p.results){
    const id=externalId(f.id);allFixtures.add(id);matches++;
    const stored=byFixture.get(id);if(!stored)missingFixtures.push(id);
    else if(f.status==='finished'&&stored.status!=='FT')statusDifferences.push({id,stored:stored.status,provider:f.status});
   }offset=p.next;
  }while(offset!=null);
  const report={league,season:season.year,teams:clubIds.length,players:members,fixtures:matches,missingTeams,missingPlayers,wrongMembership,missingFixtures,statusDifferences};
  reports.push(report);console.log(JSON.stringify({stage:'inventory-league',...report,requests:api.requests}));
 }
 const matches=fixtures.filter(f=>allFixtures.has(String(f.id))&&f.status==='FT'),sourceById=new Map(sources.map(s=>[s.fixture_id,s]));
 const statIds=new Set(statistics.map(s=>String(s.fixture_id)+'/'+String(s.player_id))),statFixtures=new Set(statistics.map(s=>s.fixture_id));
 let missingStarters=0,missingSource=0,unconfirmed=0,missingIncidents=0,goalMismatch=0;
 for(const f of matches){
  const source=sourceById.get(f.id);if(!source){missingSource++;continue;}
  const lineup=source.lineups as {lineup_status?:string;lineups?:Record<string,{players?:{id:number}[]}>}|null;
  if(lineup?.lineup_status!=='confirmed')unconfirmed++;
  for(const side of Object.values(lineup?.lineups??{}))for(const player of side.players??[])if(!statIds.has(String(f.id)+'/'+externalId(player.id)))missingStarters++;
  const incidents=(source.incidents as {incidents?:{type:string;is_home?:boolean;cancelled?:boolean;disallowed?:boolean}[]}|null)?.incidents;
  if(!Array.isArray(incidents)){missingIncidents++;continue;}
  const goals=incidents.filter(e=>e.type==='goal'&&!e.cancelled&&!e.disallowed);
  if(goals.filter(e=>e.is_home===true).length!==f.home_score||goals.filter(e=>e.is_home===false).length!==f.away_score)goalMismatch++;
 }
 const reference=policy.data?.report_reference;
 let diagnostic:Record<string,unknown>={status:reference?.status,completed:reference?.completed,total:reference?.fixtureCount};
 if(reference?.checkpoint?.path){
  const blob=checked(await db.storage.from('kickx-calculation-archives').download(reference.checkpoint.path));
  if(!blob)throw new Error('AUDIT_CHECKPOINT_UNAVAILABLE');
  const checkpoint=JSON.parse(gunzipSync(Buffer.from(await blob.arrayBuffer())).toString());
  const league=checkpoint.leagues[checkpoint.leagueIndex],fixture=league?.fixtures[checkpoint.fixtureIndex];
  diagnostic={...diagnostic,leagueIndex:checkpoint.leagueIndex,fixtureIndex:checkpoint.fixtureIndex,league:league?.id,fixture};
  if(fixture){
   try{
    const base=`/api/v2/events/${fixture}/`;
    const detail=await api.get(base),stats=await api.get(base+'player-stats/'),lineups=await api.get(base+'lineups/'),incidents=await api.get(base+'incidents/');
    const results=stats.player_stats.map((s:{player_id:number;team_id:number;minutes_played:number})=>calculatePerformance({fixtureId:externalId(fixture),playerId:externalId(s.player_id),teamId:externalId(s.team_id),status:'FT',homeTeam:externalId(detail.home_team_id),awayTeam:externalId(detail.away_team_id),homeScore:detail.home_score,awayScore:detail.away_score,stats:s,legacy:null,source:{detail,lineups,incidents},durationMinutes:observedMatchDuration(stats.player_stats.map((r:{minutes_played:number})=>r.minutes_played))}));
    diagnostic={...diagnostic,providerStatus:detail.status,resourceIds:[detail.id,stats.event_id,lineups.event_id,incidents.event_id],expectedSeasonId:league.seasonId,actualSeasonId:detail.season_id,playerStats:stats.player_stats.length,resultStatuses:results.reduce((a:Record<string,number>,r:{status:string})=>{a[r.status]=(a[r.status]??0)+1;return a;},{})};
   }catch(error){diagnostic={...diagnostic,error:error instanceof SyncError?error.code:'AUDIT_REFERENCE_RESOURCE_UNAVAILABLE'};}
  }
 }
 const report={asOf:new Date().toISOString(),totals:{teams:allTeams.size,players:allPlayers.size,fixtures:allFixtures.size,finished:matches.length,missingMatchStatistics:matches.filter(f=>!statFixtures.has(f.id)).length,missingStarterStatistics:missingStarters,missingSource,unconfirmedLineups:unconfirmed,missingIncidents,goalTimelineMismatch:goalMismatch,missingMinutes:statistics.filter(s=>allFixtures.has(String(s.fixture_id))&&s.minutes==null).length},leagues:reports,referenceDiagnostic:diagnostic,requests:api.requests};
 await mkdir('test-artifacts',{recursive:true});await writeFile('test-artifacts/valuation-inventory.json',JSON.stringify(report,null,2));
 console.log(JSON.stringify({stage:'inventory-complete',...report}));
}
main().catch(error=>{console.error(JSON.stringify({error:error instanceof SyncError?error.code:error instanceof Error&&/^[A-Z_]+$/.test(error.message)?error.message:'AUDIT_FAILED'}));process.exitCode=1;});

