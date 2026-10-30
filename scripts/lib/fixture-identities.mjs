// Resolve a missing foreign key only through a unique composite natural key:
// the same fixture's statistics, the same team, exact full name AND short name.
// Names are never fuzzily matched and an existing provider ID is never replaced.
const text=v=>typeof v==='string'?v.normalize('NFC').trim().replace(/\s+/g,' '):'';
const valid=v=>Number.isSafeInteger(v)&&v>0;
export function resolveFixtureIdentities({detail,stats,lineups,incidents},profiles){
 const sheets=structuredClone(lineups),events=structuredClone(incidents),proof=[];
 const roster=stats.player_stats??[],byId=new Map(profiles.map(p=>[Number(String(p.id).replace(/^bsd-/,'')),p]));
 if(lineups.lineup_status!=='confirmed'||stats.event_id!==detail.id||lineups.event_id!==detail.id||incidents.event_id!==detail.id)return {lineups:sheets,incidents:events,proof};
 if(new Set(roster.map(p=>p.player_id)).size!==roster.length)return {lineups:sheets,incidents:events,proof};
 const sides=Object.values(sheets.lineups??{});
 for(const side of sides){
  if(![detail.home_team_id,detail.away_team_id].includes(side.team_id))continue;
  const entries=[...(side.players??[]),...(side.substitutes??[])],pending=[];
  for(const entry of entries){
   if(entry.id!=null||!text(entry.name)||!text(entry.short_name))continue;
   const candidates=roster.filter(s=>s.team_id===side.team_id&&valid(s.player_id)).filter(s=>{
    const p=byId.get(s.player_id);return p&&[p.name,p.english].some(n=>text(n)===text(entry.name))&&text(p.short_name)===text(entry.short_name);
   });
   if(candidates.length===1)pending.push({entry,id:candidates[0].player_id});
  }
  for(const p of pending){
   if(entries.some(e=>e!==p.entry&&e.id===p.id)||pending.filter(q=>q.id===p.id).length!==1)continue;
   p.entry.id=p.id;proof.push({kind:'teamsheet',teamId:side.team_id,playerId:p.id,name:p.entry.name,shortName:p.entry.short_name});
  }
 }
 for(const e of events.incidents??[]){
  if(typeof e.is_home!=='boolean'||!['goal','card','substitution','varDecision','penalty_missed'].includes(e.type))continue;
  const side=sides.find(s=>s.team_id===(e.is_home?detail.home_team_id:detail.away_team_id));if(!side)continue;
  const entries=[...(side.players??[]),...(side.substitutes??[])].filter(p=>valid(p.id)&&roster.some(s=>s.player_id===p.id&&s.team_id===side.team_id));
  for(const [idField,nameField]of [['player_id','player'],['player_in_id','player_in'],['player_out_id','player_out']]){
   if(e[idField]!=null||!text(e[nameField]))continue;
   const candidates=entries.filter(p=>[p.name,p.short_name].some(n=>text(n)===text(e[nameField])));
   if(candidates.length!==1)continue;
   e[idField]=candidates[0].id;proof.push({kind:'incident',teamId:side.team_id,playerId:e[idField],field:idField,minute:e.minute});
  }
 }
 return {lineups:sheets,incidents:events,proof};
}
export async function loadFixtureProfiles(db){
 const profiles=[];
 for(let at=0;at<20000;at+=500){
  const r=await db.from('players').select('id,name,english,short_name').eq('provider','bsd').order('id').range(at,at+499);
  if(r.error)throw Error('IDENTITY_PROFILES_RETRY');profiles.push(...r.data);if(r.data.length<500)return profiles;
 }
 throw Error('IDENTITY_PROFILE_LIMIT');
}
