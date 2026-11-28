import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync,readdirSync} from 'node:fs';
import {PGlite} from '@electric-sql/pglite';
import {loadTs} from './load-ts.mjs';
const policy=loadTs('../server/kickx/engine/report-policy.ts');
const {calculateAdjustments:adjust,calculatePerformance:calc}=loadTs('../server/kickx/engine/report-performance.ts',{'./report-policy':policy});
const at=(result,metric)=>result.breakdown.find(b=>b.metric===metric)?.points;
const losses={total_pass:20,accurate_pass:14,expected_goals:1.4,big_chance_missed:2,error_lead_to_a_goal:1,error_lead_to_a_shot:2,dispossessed:3,possession_lost:20,unsuccessful_touch:4,duel_lost:5,aerial_lost:2,fouls:2,goals_prevented:-.7};
function match(position='F'){
 return {fixtureId:'bsd-1',playerId:'bsd-2',teamId:'bsd-1',status:'FT',homeTeam:'bsd-1',awayTeam:'bsd-2',homeScore:1,awayScore:0,
 stats:{minutes_played:90,goals:1,...losses},legacy:null,source:{detail:{stage:'league-phase'},lineups:{lineup_status:'confirmed',lineups:{home:{team_id:1,players:Array.from({length:11},(_,i)=>({id:i+1,position:i===1?position:'D'})),substitutes:[]},away:{team_id:2,players:Array.from({length:11},(_,i)=>({id:i+12,position:'D'})),substitutes:[]}}},incidents:{incidents:[{type:'goal',player_id:2,is_home:true,minute:20}]}}};
}
test('every requested deduction contributes with its published weight and signed goalkeeper value',()=>{
 const r=adjust(losses,1,'GK');
 assert.deepEqual(r.breakdown.map(b=>[b.metric,b.points]),[
 ['pass_accuracy',-1],['xg_underperformance',-.8],['big_chance_missed',-2],['error_lead_to_a_goal',-3],['error_lead_to_a_shot',-2],
 ['dispossessed',-.6],['possession_lost',-1],['unsuccessful_touch',-.4],['duel_lost',-.5],['aerial_lost',-.2],['fouls',-.5],['goals_prevented',-.7],
 ]);
 assert.equal(Math.round(r.breakdown.reduce((sum,b)=>sum+b.points,0)*100)/100,-12.7);
 assert.equal(at(adjust({...losses,goals_prevented:1.25},1,'GK'),'goals_prevented'),1.25);
 assert.equal(at(adjust(losses,1,'FW'),'goals_prevented'),undefined);
});
test('pass accuracy is shared by all positions, centered at 80%, capped, and shrunk for small samples',()=>{
 for(const position of ['GK','DF','MF','FW'])for(const [completed,points]of [[20,2],[18,1],[17,.5],[16,0],[14,-1],[12,-2],[0,-2]]){
  assert.equal(at(adjust({total_pass:20,accurate_pass:completed},0,position),'pass_accuracy'),points,`${position}/${completed}`);
 }
 for(const [attempts,completed,points]of [[1,1,.1],[10,10,1],[200,200,2],[200,160,0],[1,0,-.1]]){
  assert.equal(at(adjust({total_pass:attempts,accurate_pass:completed},0,'FW'),'pass_accuracy'),points);
 }
 assert.equal(at(adjust({total_pass:0,accurate_pass:0},0,'MF'),'pass_accuracy'),undefined);
 assert.equal(at(adjust({total_pass:20,accurate_pass:null},0,'MF'),'pass_accuracy'),undefined);
 assert.equal(adjust({total_pass:10,accurate_pass:11},0,'GK').invalidPass,true);
});
test('finishing penalties use the verified goal deficit without a second positive goal bonus',()=>{
 assert.equal(at(adjust({expected_goals:1.4},1,'FW'),'xg_underperformance'),-.8);
 assert.equal(at(adjust({expected_goals:.4},1,'FW'),'xg_underperformance'),0);
 assert.equal(at(adjust({expected_goals:null},0,'FW'),'xg_underperformance'),undefined);
});
test('total shots and xGOT never enter the new adjustments; invalid optional counters never invent failures',()=>{
 assert.deepEqual(adjust({...losses,total_shots:999,expected_goals_on_target:999},1,'GK'),adjust(losses,1,'GK'));
 const r=adjust({expected_goals:-1,big_chance_missed:-2,error_lead_to_a_goal:'1',fouls:1.5,goals_prevented:Infinity},0,'GK');
 assert.equal(r.breakdown.length,0);assert(r.warnings.length>0);
 assert.equal(Object.is(at(adjust({goals_prevented:-.005},0,'GK'),'goals_prevented'),-0),false);
});
test('full scoring removes both old pass bonuses, retains verified goals, and can become negative',()=>{
 const m=match();const current=calc(m),previous=calc(m,policy.PREVIOUS_SCORING_REVISION);
 assert.equal(current.status,'provisional');assert.equal(current.score,-6);assert.equal(at(current,'goals'),4);
 assert.equal(at(current,'passes_completed'),undefined);assert.equal(at(current,'pass_accuracy'),-1);
 assert.equal(previous.score,6.5);assert.equal(at(previous,'passes_completed'),.5);assert.equal(at(previous,'fouls'),undefined);
 m.stats.accurate_pass=21;assert(calc(m).warnings.includes('INVALID_PASS_TOTALS'));
});
test('a rolling deployment publishes the scorer revision selected by the database policy',async()=>{
 for(const revision of [policy.PREVIOUS_SCORING_REVISION,policy.SCORING_REVISION]){
  const m=match();let saved;
  const {calculatePlayer}=loadTs('../server/kickx/engine/service.ts',{
   'server-only':{},'node:crypto':{createHash},'./performance':{RULE_VERSION:'form-v2'},'./legacy-performance':{},'./pricing':{},
   './report-performance':{calculatePerformance:calc},'./report-policy':policy,
   '../http':{HttpError:class extends Error{}},'../prototype':{checkDatabase:error=>{if(error)throw error;}},
  });
  const db={rpc:async(name,args)=>{
   if(name==='kickx_calculation_input')return {data:{policy:{version:'report-v3',report_parameters:{scoringRevision:revision}},token:'policy-token',records:[{
    player_id:m.playerId,fixture_id:m.fixtureId,team_id:m.teamId,stats:m.stats,legacy_stats:null,fixtures:{id:m.fixtureId,league_id:'bsd-1',status:'FT',home_team_id:m.homeTeam,away_team_id:m.awayTeam,home_score:1,away_score:0,football_event_sources:m.source},
   }]},error:null};
   assert.equal(name,'kickx_publish_calculation_delta');saved=args;return {data:{unchanged:false},error:null};
  }};
  await calculatePlayer(db,m.playerId,null);assert.equal(saved.p_results[0].scoringRevision,revision);
  assert.equal(saved.p_results[0].score,revision===policy.SCORING_REVISION?-6:6.5);
 }
});
test('PostgreSQL historical replay and the live TypeScript adjustments agree on real-valued and corrupt inputs',async()=>{
 const db=new PGlite();
 try{
  await db.exec(await readFileSync(new URL('./database-bootstrap.sql',import.meta.url),'utf8'));
  await db.exec('create schema kickx_private');
  const file=readdirSync(new URL('../supabase/migrations/',import.meta.url)).find(x=>x.endsWith('_balanced_performance_adjustments.sql'));
  const sql=readFileSync(new URL('../supabase/migrations/'+file,import.meta.url),'utf8').split('-- Bounded-size metadata fingerprints')[0];
  await db.exec(sql+'\ncommit;');
  let seed=20261128;const random=()=>{seed=(seed*1664525+1013904223)>>>0;return seed/4294967296;};
  const cases=[losses,{total_pass:1,accurate_pass:1},{total_pass:20,accurate_pass:0},{goals_prevented:-.005},{expected_goals:1.0025},{}];
  for(let i=0;i<90;i++){
   const attempts=1+Math.floor(random()*100),stats={total_pass:attempts,accurate_pass:Math.floor(random()*(attempts+1)),expected_goals:Math.round(random()*300)/100,goals_prevented:Math.round((random()*6-3)*100)/100};
   for(const key of ['big_chance_missed','error_lead_to_a_goal','error_lead_to_a_shot','dispossessed','possession_lost','unsuccessful_touch','duel_lost','aerial_lost','fouls'])stats[key]=random()<.15?null:Math.floor(random()*8);
   cases.push(stats);
  }
  for(const [i,stats]of cases.entries())for(const position of ['GK','DF','MF','FW']){
   const goals=i%4,expected=adjust(stats,goals,position);
   const actual=(await db.query('select kickx_private.balanced_adjustments($1,$2,$3) as result',[stats,goals,position])).rows[0].result;
   assert.deepEqual(actual,expected,`case ${i}/${position}`);
  }
 }finally{await db.close();}
});
