import {createClient} from '@supabase/supabase-js';
import {gunzipSync} from 'node:zlib';
import {createHash} from 'node:crypto';
import {mkdir,writeFile} from 'node:fs/promises';
import {nameImportFetch} from './lib/korean-catalog.mjs';
import {createFootballClient,normalizeStatus} from './lib/football.mjs';
const checked=r=>{if(r.error)throw Error('REFERENCE_QUALITY_DATABASE_RETRY');return r.data;};
const sample=p=>({keys:Object.keys(p),id:p.id,playerId:p.player_id,position:p.position,pos:p.pos,role:p.role,grid:p.grid,nestedPlayer:p.player?{id:p.player.id,position:p.player.position}:null});
const describe=d=>({statsRows:d.stats?.player_stats?.length??null,declaredStats:d.stats?.count??null,lineupStatus:d.lineups?.lineup_status??null,
 homeStarters:d.lineups?.lineups?.home?.players?.length??0,awayStarters:d.lineups?.lineups?.away?.players?.length??0,incidents:d.incidents?.incidents?.length??null,
 status:d.detail?.status,normalizedStatus:normalizeStatus(d.detail),extraTimeScore:d.detail?.extra_time_score,shootout:d.detail?.penalty_shootout,
 positiveMinutes:d.stats?.player_stats?.filter(s=>s.minutes_played>0).length??0,
 lineupSamples:(d.lineups?.lineups?.home?.players??[]).slice(0,3).map(sample),statisticsSamples:(d.stats?.player_stats??[]).slice(0,3).map(p=>({playerId:p.player_id,teamId:p.team_id,minutes:p.minutes_played,position:p.position})),
 priorResultReasons:(d.results??[]).reduce((out,r)=>{if(r.status==='blocked'){const reason=r.warnings?.at(-1)??'unknown';out[reason]=(out[reason]??0)+1;}return out;},{})});
async function main(){
 const key=process.env.SUPABASE_SERVICE_ROLE_KEY;
 const db=createClient(process.env.SUPABASE_URL,key,{global:{fetch:nameImportFetch(key)},auth:{persistSession:false,autoRefreshToken:false}});
 const ref=checked(await db.from('kickx_policy').select('report_reference').single()).report_reference;
 const valid=new Set(Object.values(ref.players).flatMap(p=>Object.values(p).flatMap(h=>h.fixtures)));
 const samplesOnly=process.argv.includes('--samples');
 const archives=samplesOnly?ref.leagues.flatMap(l=>[ref.archives.find(a=>a.league===l.id&&!valid.has(a.fixtureId)),ref.archives.find(a=>a.league===l.id&&valid.has(a.fixtureId))].filter(Boolean)):ref.archives;
 const leagues=new Map(ref.leagues.map(l=>[l.id,{league:l.id,archives:0,scorableFixtures:0,emptyStats:0,unconfirmedLineups:0,missingIncidents:0,statisticsRows:0,examples:[]}]))
 const unavailable=[];
 for(let at=0;at<archives.length;at+=8){
  const results=await Promise.allSettled(archives.slice(at,at+8).map(async a=>{
   const blob=checked(await db.storage.from('kickx-calculation-archives').download(a.path));
   const bytes=Buffer.from(await blob.arrayBuffer());if(createHash('sha256').update(bytes).digest('hex')!==a.hash)throw Error('REFERENCE_QUALITY_ARCHIVE_HASH');
   const d=JSON.parse(gunzipSync(bytes,{maxOutputLength:15*1024*1024}).toString());
   if(d.fixtureId!==a.fixtureId||d.detail.league_id!==a.league)throw Error('REFERENCE_QUALITY_IDENTITY');
   return {a,d,facts:describe(d)};
  }));
  for(const item of results){
   if(item.status!=='fulfilled')throw item.reason;const {a,d,facts}=item.value,l=leagues.get(a.league);
   l.archives++;l.scorableFixtures+=Number(valid.has(a.fixtureId));l.emptyStats+=Number(facts.statsRows===0);l.unconfirmedLineups+=Number(facts.lineupStatus!=='confirmed');l.missingIncidents+=Number(facts.incidents===null);l.statisticsRows+=facts.statsRows??0;
   const example={fixtureId:a.fixtureId,date:d.detail.event_date,home:d.detail.home_team,away:d.detail.away_team,scorable:valid.has(a.fixtureId),...facts};
   if(l.examples.filter(x=>x.scorable===example.scorable).length<2)l.examples.push(example);
   if(!valid.has(a.fixtureId)&&!unavailable.some(x=>x.league===a.league))unavailable.push({...example,league:a.league});
  }
  if(at%400===0)console.log(JSON.stringify({stage:'reference-quality-progress',checked:Math.min(at+8,ref.archives.length)}));
 }
 const budget=checked(await db.from('football_bulk_daily_budget').select('requests').eq('day',new Date().toISOString().slice(0,10)).maybeSingle());
 const fresh=[];
 if((budget?.requests??0)<5500){
  const api=createFootballClient({key:process.env.BSD_API_KEY,budget:25,delay:100,fetchImpl:async(...args)=>{checked(await db.rpc('kickx_reserve_provider_request'));return fetch(...args);}});
  for(const old of unavailable){
   try {
   const base=`/api/v2/events/${old.fixtureId.slice(4)}/`;
   const [detail,stats,lineups,incidents]=await Promise.all([base,base+'player-stats/',base+'lineups/',base+'incidents/'].map(path=>api.get(path)));
   if(`bsd-${detail.id}`!==old.fixtureId||detail.league_id!==old.league)throw Error('REFERENCE_QUALITY_FRESH_IDENTITY');
   fresh.push({fixtureId:old.fixtureId,league:old.league,archivedStats:old.statsRows,...describe({detail,stats,lineups,incidents})});
   } catch {fresh.push({fixtureId:old.fixtureId,league:old.league,error:'PROVIDER_RECHECK_UNAVAILABLE'});}
  }
 }
 const latest=checked(await db.from('kickx_policy').select('hash:report_reference->hash').single());if(latest.hash!==ref.hash)throw Error('REFERENCE_QUALITY_CHANGED');
 const report={stage:'reference-quality-complete',checkedAt:new Date().toISOString(),referenceHash:ref.hash,archives:archives.length,samplesOnly,referenceArchives:ref.archives.length,scorableFixtures:valid.size,
  archivesHashVerified:true,leagues:[...leagues.values()],freshChecks:fresh,freshChecksDeferred:!fresh.length&&unavailable.length>0};
 await mkdir('test-artifacts',{recursive:true});await writeFile('test-artifacts/reference-quality.json',JSON.stringify(report,null,2));console.log(JSON.stringify(report));
}
main().catch(()=>{console.error('REFERENCE_QUALITY_RETRY');process.exitCode=1;});
