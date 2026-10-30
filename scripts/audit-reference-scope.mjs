import {createClient} from '@supabase/supabase-js';
import {gunzipSync} from 'node:zlib';
import {createHash} from 'node:crypto';
import {createFootballClient} from './lib/football.mjs';
import {nameImportFetch} from './lib/korean-catalog.mjs';
const key=process.env.SUPABASE_SERVICE_ROLE_KEY;
const db=createClient(process.env.SUPABASE_URL,key,{global:{fetch:nameImportFetch(key)},auth:{persistSession:false,autoRefreshToken:false}});
const checked=r=>{if(r.error)throw Error('SCOPE_DATABASE_RETRY');return r.data;};
const descriptor=checked(await db.from('kickx_policy').select('report_reference').single()).report_reference;
let ref=descriptor;
if(descriptor.checkpoint){
 const blob=checked(await db.storage.from('kickx-calculation-archives').download(descriptor.checkpoint.path));
 const bytes=Buffer.from(await blob.arrayBuffer());
 if(createHash('sha256').update(bytes).digest('hex')!==descriptor.checkpoint.hash)throw Error('INVALID_CHECKPOINT');
 ref=JSON.parse(gunzipSync(bytes).toString());
}
const api=createFootballClient({key:process.env.BSD_API_KEY,budget:25,delay:1200,fetchImpl:async(...args)=>{checked(await db.rpc('kickx_reserve_provider_request'));return fetch(...args);}});
console.log(JSON.stringify({stage:'scope-counts',leagues:ref.leagues.map(l=>({id:l.id,count:l.fixtures.length,season:l.seasonId}))}));
for(const league of ref.leagues.filter(l=>[5,6].includes(l.id)))for(const id of league.fixtures.slice(-5)){
 const d=await api.get(`/api/v2/events/${id}/`);
 const fields=['league_id','season_id','event_date','home_team_id','home_team','away_team_id','away_team','stage','round_label','round','round_name','round_number','matchday','round_type','phase','type','competition_kind','competition_stage'];
 console.log(JSON.stringify({stage:'scope-fixture',id,league:league.id,keys:Object.keys(d),detail:Object.fromEntries(fields.map(k=>[k,d[k]]))}));
}
