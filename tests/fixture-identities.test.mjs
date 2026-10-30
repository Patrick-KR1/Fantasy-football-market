import test from 'node:test';
import assert from 'node:assert/strict';
import {resolveFixtureIdentities as resolve} from '../scripts/lib/fixture-identities.mjs';
const profiles=[{id:'bsd-10',name:'Alex Player',short_name:'A. Player'},{id:'bsd-20',name:'Alex Player',short_name:'A. Player'}];
const fixture=()=>({detail:{id:1,home_team_id:2,away_team_id:3},stats:{event_id:1,player_stats:[{player_id:10,team_id:2},{player_id:20,team_id:3}]},lineups:{event_id:1,lineup_status:'confirmed',lineups:{home:{team_id:2,players:[{id:null,name:'Alex Player',short_name:'A. Player',position:'D'}],substitutes:[]},away:{team_id:3,players:[{id:20,name:'Alex Player',short_name:'A. Player',position:'M'}],substitutes:[]}}},incidents:{event_id:1,incidents:[{type:'goal',minute:5,is_home:true,player:'A. Player',player_id:null}]}});
test('missing IDs require an exact unique full-name/short-name pair in the fixture team',()=>{
 const f=fixture(),r=resolve(f,profiles);assert.equal(r.lineups.lineups.home.players[0].id,10);assert.equal(r.lineups.lineups.home.players[0].position,'D');assert.equal(r.incidents.incidents[0].player_id,10);assert.equal(f.lineups.lineups.home.players[0].id,null);
 f.lineups.lineups.home.players[0].short_name='A Player';assert.equal(resolve(f,profiles).lineups.lineups.home.players[0].id,null);
});
test('ambiguous identities, duplicate assignments and foreign fixture data remain unresolved',()=>{
 const f=fixture();f.stats.player_stats[1].team_id=2;assert.equal(resolve(f,profiles).lineups.lineups.home.players[0].id,null);
 const g=fixture();g.lineups.lineups.home.players.push({...g.lineups.lineups.home.players[0]});assert.ok(resolve(g,profiles).lineups.lineups.home.players.every(p=>p.id===null));
 const h=fixture();h.stats.event_id=99;assert.equal(resolve(h,profiles).lineups.lineups.home.players[0].id,null);
});
test('provided IDs and exact historical positions are preserved',()=>{
 const f=fixture();f.lineups.lineups.home.players[0].id=77;const r=resolve(f,profiles);assert.equal(r.lineups.lineups.home.players[0].id,77);assert.equal(r.lineups.lineups.away.players[0].position,'M');assert.equal(r.incidents.incidents[0].player_id,null);
});
