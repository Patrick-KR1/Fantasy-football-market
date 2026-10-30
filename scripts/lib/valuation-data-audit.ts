type Row=Record<string,unknown>;
type Lineup={lineup_status?:string;lineups?:Record<string,{players?:{id:number}[]}>};
type Event={type?:string;is_home?:boolean;cancelled?:boolean;disallowed?:boolean};
const leagues=new Set(['bsd-1','bsd-3','bsd-4','bsd-5','bsd-6']);

/** Inspect compact, paged evidence in the worker. Never scan all raw JSON in one RPC. */
export function inspectValuationData({players,fixtures,statistics,sources,currentTeamIds}: {
 players:Row[];fixtures:Row[];statistics:Row[];sources:Row[];currentTeamIds:Set<string>;
}) {
 const finished=fixtures.filter(f=>leagues.has(String(f.league_id))&&f.status==='FT');
 const finishedIds=new Set(finished.map(f=>String(f.id)));
 const bySource=new Map(sources.map(s=>[String(s.fixture_id),s]));
 const statKeys=new Set(statistics.map(s=>`${s.fixture_id}/${s.player_id}`));
 const statFixtures=new Set(statistics.map(s=>String(s.fixture_id)));
 const repairFixtures=new Set<string>();
 let missingStarterStatistics=0,missingMatchSources=0,unconfirmedLineups=0,missingIncidents=0,goalTimelineMismatch=0,missingMinutes=0;
 for(const f of finished){
  const id=String(f.id),s=bySource.get(id),lineups=s?.lineups as Lineup|null;
  const incidents=(s?.incidents as {incidents?:Event[]}|null)?.incidents;
  if(!statFixtures.has(id))repairFixtures.add(id);
  if(!s||s.lineups==null||s.incidents==null){missingMatchSources++;repairFixtures.add(id);}
  if(lineups?.lineup_status!=='confirmed'){unconfirmedLineups++;repairFixtures.add(id);}
  for(const side of Object.values(lineups?.lineups??{}))for(const player of side.players??[]){
   if(!statKeys.has(`${id}/bsd-${player.id}`)){missingStarterStatistics++;repairFixtures.add(id);}
  }
  if(!Array.isArray(incidents)){missingIncidents++;repairFixtures.add(id);continue;}
  const goals=incidents.filter(e=>e.type==='goal'&&!e.cancelled&&!e.disallowed);
  if(goals.filter(e=>e.is_home===true).length!==f.home_score||goals.filter(e=>e.is_home===false).length!==f.away_score){goalTimelineMismatch++;repairFixtures.add(id);}
 }
 for(const s of statistics)if(finishedIds.has(String(s.fixture_id))&&s.minutes==null){missingMinutes++;repairFixtures.add(String(s.fixture_id));}
 return {missingStarterStatistics,missingMatchSources,unconfirmedLineups,missingIncidents,missingMinutes,goalTimelineMismatch,
  missingCurrentRosterPosition:players.filter(p=>currentTeamIds.has(String(p.team_id))&&p.position==null).length,
  repairFixtures:[...repairFixtures].sort()};
}
