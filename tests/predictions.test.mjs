import test from 'node:test';
import assert from 'node:assert/strict';
import { loadTs } from './load-ts.mjs';
const validation=loadTs('../lib/kickx/validation.ts');
const http=loadTs('../server/kickx/http.ts',{'server-only':{},'@/lib/kickx/validation':validation,'./config':{},'./supabase':{}});
const prototype=loadTs('../server/kickx/prototype.ts',{'server-only':{},'./http':http,'@/lib/kickx/squad':loadTs('../lib/kickx/squad.ts')});
const request=(body,origin='https://kickx.invalid')=>new Request('https://kickx.invalid/api/kickx/predictions',{method:'POST',headers:{origin,'Content-Type':'application/json'},body:JSON.stringify(body)});
test('prediction API verifies authentication and origin, validates picks and ignores forged rewards or recipients',async()=>{
 let authenticated=false;const calls=[];
 const route=loadTs('../app/api/kickx/predictions/route.ts',{'@/server/kickx/http':{...http,authenticatedClient:async()=>{if(!authenticated)throw new http.HttpError(401,'로그인');return {client:{rpc:async(name,args)=>{calls.push({name,args});return {data:{teamId:'main',past:[],upcoming:[]},error:null};}}};}},'@/server/kickx/prototype':prototype});
 assert.equal((await route.GET()).status,401);
 assert.equal((await route.POST(request({}))).status,401);authenticated=true;
 assert.equal((await route.POST(request({},'https://foreign.invalid'))).status,403);
 for(const choice of ['other',null,['win'],{},0])assert.equal((await route.POST(request({fixtureId:'bsd-123',choice}))).status,400);
 assert.equal((await route.POST(request({fixtureId:'bad fixture',choice:'win'}))).status,400);
 assert.equal(calls.length,0);
 assert.equal((await route.POST(request({fixtureId:'bsd-123',choice:'win',userId:'another-member',teamId:'other',reward:9999999,actual:'win'}))).status,200);
 assert.deepEqual(calls[0],{name:'kickx_predict',args:{p_fixture:'bsd-123',p_choice:'win'}});
 const result=await route.GET();assert.equal(result.status,200);assert.match(result.headers.get('Cache-Control'),/private, no-store/);
 assert.deepEqual(calls[1],{name:'kickx_predictions',args:undefined});
});
test('prediction errors give a useful closed-window message',()=>{
 assert.throws(()=>prototype.checkDatabase({message:'PREDICTION_CLOSED'}),error=>error.status===409&&error.message.includes('마감'));
 assert.throws(()=>prototype.checkDatabase({message:'PREDICTION_UNAVAILABLE'}),error=>error.status===409&&error.message.includes('3경기'));
});
