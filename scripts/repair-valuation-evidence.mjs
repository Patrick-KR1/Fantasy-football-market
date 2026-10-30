import {createClient} from '@supabase/supabase-js';
import {mkdir,writeFile} from 'node:fs/promises';
import {createFootballClient} from './lib/football.mjs';
import {nameImportFetch} from './lib/korean-catalog.mjs';
import {gunzipSync} from 'node:zlib';
import {createHash} from 'node:crypto';
import {resolveFixtureIdentities,loadFixtureProfiles} from './lib/fixture-identities.mjs';
import {normalizeStatus} from './lib/football.mjs';
const checked=r=>{if(r.error)throw Error(`EVIDENCE_DATABASE_${/^[A-Z0-9]+$/.test(r.error.code??'')?r.error.code:'RETRY'}`);return r.data;};
async function main(){
 const key=process.env.SUPABASE_SERVICE_ROLE_KEY;
 const db=createClient(process.env.SUPABASE_URL,key,{global:{fetch:nameImportFetch(key)},auth:{persistSession:false,autoRefreshToken:false}});
 if(process.argv.includes('--identity-preview')){
  const {calculatePerformance}=await import('../server/kickx/engine/report-performance.ts');
  const {observedMatchDuration}=await import('./lib/report-reference.ts');
  const ref=checked(await db.from('kickx_policy').select('report_reference').single()).report_reference;
  const profiles=await loadFixtureProfiles(db),valid=new Set(Object.values(ref.players).flatMap(p=>Object.values(p).flatMap(h=>h.fixtures))),results=[];
  for(const league of ref.leagues){
   const a=ref.archives.find(a=>a.league===league.id&&!valid.has(a.fixtureId));if(!a)continue;
   const blob=checked(await db.storage.from('kickx-calculation-archives').download(a.path)),bytes=Buffer.from(await blob.arrayBuffer());
   if(createHash('sha256').update(bytes).digest('hex')!==a.hash)throw Error('IDENTITY_ARCHIVE_HASH');
   const d=JSON.parse(gunzipSync(bytes).toString()),resolved=resolveFixtureIdentities(d,profiles),duration=observedMatchDuration(d.stats.player_stats.map(s=>s.minutes_played),d.stats.player_stats,resolved.incidents);
   const scores=d.stats.player_stats.map(s=>calculatePerformance({fixtureId:a.fixtureId,playerId:`bsd-${s.player_id}`,teamId:`bsd-${s.team_id}`,status:normalizeStatus(d.detail),homeTeam:`bsd-${d.detail.home_team_id}`,awayTeam:`bsd-${d.detail.away_team_id}`,homeScore:d.detail.home_score,awayScore:d.detail.away_score,stats:s,legacy:null,source:{detail:d.detail,lineups:resolved.lineups,incidents:resolved.incidents},durationMinutes:duration,regularSeasonOnly:true}));
   results.push({fixtureId:a.fixtureId,league:league.id,resolved:resolved.proof.length,scorable:scores.filter(r=>r.score!=null).length,reasons:scores.filter(r=>r.status==='blocked').reduce((m,r)=>{const k=r.warnings.at(-1);m[k]=(m[k]??0)+1;return m;},{})});
  }
  await mkdir('test-artifacts',{recursive:true});await writeFile('test-artifacts/identity-preview.json',JSON.stringify(results,null,2));console.log(JSON.stringify({stage:'identity-preview',results}));return;
 }
 const api=createFootballClient({key:process.env.BSD_API_KEY,budget:15,delay:100,fetchImpl:async(...args)=>{checked(await db.rpc('kickx_reserve_provider_request'));return fetch(...args);}});
 const replies=await Promise.all(['GOAL_BOUNDARY_TIME_AMBIGUOUS','MINUTES_INTERVAL_MISMATCH'].map(reason=>db.from('performance_results').select('fixture_id').eq('status','blocked').filter('warnings','cs',JSON.stringify([reason])).order('fixture_id').limit(1)));
 const ids=[...new Set(replies.flatMap(r=>checked(r).map(x=>x.fixture_id)))];
 const matches=[];
 for(const id of ids){
  const fetched=await Promise.allSettled(['commentary/','incidents/'].map(s=>api.get(`/api/v2/events/${id.slice(4)}/${s}`)));
  const [commentary,incidents]=fetched.map(r=>r.status==='fulfilled'?r.value:{unavailable:true});matches.push({fixtureId:id,commentary,incidents});
 }
 let legacy;try{legacy=await api.get('/api/player-stats/',{event:1});}catch(e){legacy={unavailable:true,code:/^[A-Z0-9_]+$/.test(e.code??'')?e.code:'PROVIDER_RETRY'};}
 const report={checkedAt:new Date().toISOString(),matches,legacy};
 await mkdir('test-artifacts',{recursive:true});await writeFile('test-artifacts/valuation-evidence-probe.json',JSON.stringify(report));
 console.log(JSON.stringify({stage:'evidence-probe',matches:matches.map(m=>({fixtureId:m.fixtureId,keys:Object.keys(m.commentary),lines:m.commentary.commentary?.length,withSeconds:m.commentary.commentary?.filter(l=>l.second!=null).length,sample:m.commentary.commentary?.filter(l=>['goal','substitution','period_end','var','red_card'].includes(l.type)).slice(0,6)})),legacyKeys:Object.keys(legacy),legacySamples:legacy.results?.slice(0,2),requests:api.requests}));
 if(process.argv.includes('--apply')){
  const {calculatePlayer}=await import('../server/kickx/engine/service.ts');
  const integrity=checked(await db.rpc('kickx_valuation_integrity'));
  const affected=checked(await db.from('performance_results').select('player_id').eq('status','blocked').filter('warnings','cs',JSON.stringify(['GOAL_BOUNDARY_TIME_AMBIGUOUS'])));
  const playerIds=[...new Set(affected.map(r=>r.player_id))];
  const queued=checked(await db.from('calculation_queue').select('player_id,revision').in('player_id',playerIds));
  const revisions=new Map(queued.map(r=>[r.player_id,r.revision]));
  const forceEvidence={rpc:(name,args)=>db.rpc(name,name==='kickx_calculation_input'?{...args,p_full:true}:args)};
  const recovered=[],withheld=[],failed=[];
  for(let at=0;at<playerIds.length;at+=3){
   await Promise.all(playerIds.slice(at,at+3).map(async id=>{
    try{
     const result=await calculatePlayer(forceEvidence,id,null);
     (result.withheld?withheld:recovered).push(id);
     if(revisions.has(id))checked(await db.rpc('kickx_ack_calculation',{p_player:id,p_revision:revisions.get(id),p_error:result.withheld?'CALCULATION_WITHHELD':null}));
    }catch{failed.push(id);}
   }));
  }
  const p=checked(await db.from('kickx_policy').select('valuation_rebuild').single());
  const next={...p.valuation_rebuild};delete next.portfolioRebuiltAt;
  const staged=checked(await db.from('kickx_policy').update({valuation_rebuild:next}).eq('id',true).eq('valuation_rebuild',JSON.stringify(p.valuation_rebuild)).select('id'));
  if(staged.length!==1)throw Error('EVIDENCE_POLICY_CHANGED');
  const portfolios=checked(await db.rpc('kickx_finish_valuation_rebuild'));
  const after=checked(await db.rpc('kickx_valuation_integrity'));
  if(JSON.stringify(integrity)!==JSON.stringify(after))throw Error('EVIDENCE_FINANCIAL_INTEGRITY');
  const outcome={checkedAt:new Date().toISOString(),attempted:playerIds.length,recovered,withheld,failed,portfolios,financialIntegrityUnchanged:true};
  await writeFile('test-artifacts/valuation-recovery.json',JSON.stringify(outcome,null,2));console.log(JSON.stringify({stage:'evidence-recovery',...outcome}));
  if(failed.length)process.exitCode=1;
 }
}
main().catch(e=>{console.error(/^[A-Z0-9_]+$/.test(e.message??'')?e.message:'EVIDENCE_PROBE_RETRY');process.exitCode=1;});
