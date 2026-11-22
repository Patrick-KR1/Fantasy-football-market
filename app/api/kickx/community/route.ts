import { authenticatedClient, failure, HttpError, json, readJson, requireOrigin } from "@/server/kickx/http";
import { asObject, checkDatabase, identity, migrationMissing } from "@/server/kickx/prototype";
import { createRequestClient } from "@/server/kickx/supabase";
import { getSupabaseConfig } from "@/server/kickx/config";
import { validatePost } from "@/lib/kickx/validation";
import { parseCommunityQuery, squadMarker, stripSquadMarkers } from "@/lib/kickx/community";
import { POST_LIMITS } from "@/lib/kickx/validation";
export async function GET(request:Request){try{
 const p=new URL(request.url).searchParams;const postId=p.get("postId");
 const unavailable={status:"not-configured",data:postId?{post:null,comments:[]}:{items:[],total:0,page:1,size:20}};
 if(!getSupabaseConfig())return json(unavailable);
 const client=await createRequestClient();
 let input: ReturnType<typeof parseCommunityQuery>;
 try { input=parseCommunityQuery(p); } catch(e) { throw new HttpError(400,e instanceof Error?e.message:"검색 조건을 확인해 주세요."); }
 const focus=p.get('comment');
 const query=postId?client.rpc("kickx_post_detail",{p_id:identity(postId,true),p_page:input.page,...(focus?{p_comment:identity(focus,true)}:{})}):client.rpc("kickx_posts",{p_scope:input.scope,p_target:input.target,p_query:input.query,p_sort:input.sort,p_page:input.page,p_size:20});
 const {data,error}=await query;if(migrationMissing(error))return json(unavailable);checkDatabase(error);return json({status:"ready",data});
}catch(error){return failure(error);}}
export async function POST(request:Request){try{
 requireOrigin(request);const {client,user}=await authenticatedClient();const input=asObject(await readJson(request));const action=input.action;
 if(typeof action!=="string")throw new HttpError(400,"요청을 확인해 주세요.");
 if(action==="createPost"||action==="editPost"){
  for(const field of ["scope","target","title","body","transaction"])if(typeof input[field]!=="string")throw new HttpError(400,"글 내용을 확인해 주세요.");
  input.title=String(input.title).normalize("NFC").trim();
  input.body=stripSquadMarkers(String(input.body));
  const attachSquad=input.squad===true;delete input.squad;
  if(action==="editPost"){
   const current=await client.rpc("kickx_post_detail",{p_id:identity(input.postId,true),p_page:1});checkDatabase(current.error);
   if(!current.data?.post)throw new HttpError(404,"게시글을 찾을 수 없습니다.");
   if(current.data.post.scope!==input.scope || current.data.post.target!==input.target)throw new HttpError(409,"게시글의 선수·구단 대상을 변경할 수 없습니다.");
  }
  const profile=await client.from("profiles").select("team_id,team_ids,primary_team_id").eq("id",user.id).maybeSingle();checkDatabase(profile.error);
  const target=await client.from(input.scope==="club"?"teams":"players").select("id").eq("id",identity(input.target)).maybeSingle();checkDatabase(target.error);
  const ownTrades:string[]=[];
  if(input.transaction){
   const trade=await client.from("trades").select("id,player_id").eq("id",identity(input.transaction,true)).eq("user_id",user.id).maybeSingle();checkDatabase(trade.error);
   if(trade.data && (input.scope!=="player" || trade.data.player_id===input.target))ownTrades.push(trade.data.id);
  }
  const errors=validatePost(input as unknown as Parameters<typeof validatePost>[0],{myTeam:profile.data?.team_id??null,myTeams:profile.data?.team_ids,primaryTeam:profile.data?.primary_team_id??null,targets:target.data?[target.data.id]:[],transactions:ownTrades});
  if(Object.keys(errors).length)throw new HttpError(400,Object.values(errors).join(" "));
  if(attachSquad){
   // The snapshot is read from the author's own saved squad, never taken from the request.
   const squad=await client.from("squads").select("formation_id,slots").eq("user_id",user.id).maybeSingle();checkDatabase(squad.error);
   // The look (pitch theme and each starter's frame) is read from the author's own cosmetics too.
   const slots=(squad.data?.slots??[]) as (string|null)[];
   const [state,own]=await Promise.all([client.rpc("kickx_engagement"),client.rpc("kickx_player_frames")]);
   const loadout=(!state.error&&state.data&&typeof state.data==="object"?(state.data as {loadout?:{pitch?:string|null;frame?:string|null}}).loadout:null)??{};
   const perPlayer=(!own.error&&own.data&&typeof own.data==="object"?own.data:{}) as Record<string,string>;
   const marker=squad.data?squadMarker(String(squad.data.formation_id),slots,{pitch:loadout.pitch??null,frames:slots.map(id=>id?perPlayer[id]??loadout.frame??null:null)}):null;
   if(!marker)throw new HttpError(400,"첨부할 스쿼드가 없습니다. 스쿼드를 먼저 구성해 주세요.");
   if([...String(input.body)+marker].length>POST_LIMITS.bodyMax)throw new HttpError(400,"스쿼드를 첨부하려면 내용을 조금 줄여 주세요.");
   input.body=String(input.body)+marker;
  }
 }
 const {data,error}=await client.rpc("kickx_community_write",{p_action:action,p_input:{...input,category:"자유"}});checkDatabase(error);return json(data);
}catch(error){return failure(error);}}
