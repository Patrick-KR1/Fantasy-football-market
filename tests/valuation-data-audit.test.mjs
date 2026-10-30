import test from 'node:test';
import assert from 'node:assert/strict';
import {loadTs} from './load-ts.mjs';
const {inspectValuationData:audit}=loadTs('../scripts/lib/valuation-data-audit.ts');
function evidence(){return {players:[{id:'bsd-1',team_id:'bsd-10',position:'DF'}],fixtures:[{id:'bsd-99',league_id:'bsd-1',status:'FT',home_score:0,away_score:0}],statistics:[{player_id:'bsd-1',fixture_id:'bsd-99',minutes:0}],sources:[{fixture_id:'bsd-99',lineups:{lineup_status:'confirmed',lineups:{home:{players:[{id:1}]}}},incidents:{incidents:[]}}],currentTeamIds:new Set(['bsd-10'])};}
test('paged audit preserves a verified zero while flagging missing minutes and missing starters',()=>{
 const e=evidence();let r=audit(e);assert.equal(r.missingMinutes,0);assert.deepEqual(r.repairFixtures,[]);
 e.statistics[0].minutes=null;r=audit(e);assert.equal(r.missingMinutes,1);assert.deepEqual(r.repairFixtures,['bsd-99']);
 e.statistics=[];r=audit(e);assert.equal(r.missingStarterStatistics,1);assert.deepEqual(r.repairFixtures,['bsd-99']);
});
test('audit flags source conflicts and unknown positions without inferring unplayed games',()=>{
 const e=evidence();e.players[0].position=null;e.sources[0].incidents.incidents=[{type:'goal',is_home:true}];
 const r=audit(e);assert.equal(r.goalTimelineMismatch,1);assert.equal(r.missingCurrentRosterPosition,1);assert.equal(r.missingMinutes,0);
 e.sources=[];assert.equal(audit(e).missingMatchSources,1);assert.equal(audit(e).unconfirmedLineups,1);
});
test('audit ignores cup statistics and disallowed goals',()=>{
 const e=evidence();e.sources[0].incidents.incidents=[{type:'goal',is_home:true,disallowed:true}];
 e.fixtures.push({id:'bsd-100',league_id:'bsd-12',status:'FT',home_score:4,away_score:0});
 e.statistics.push({player_id:'bsd-1',fixture_id:'bsd-100',minutes:null});
 assert.equal(audit(e).goalTimelineMismatch,0);assert.equal(audit(e).missingMinutes,0);
});
