import { authenticatedClient, failure, HttpError, json, readJson, requireOrigin } from '@/server/kickx/http';
import { asObject, checkDatabase, identity, migrationMissing } from '@/server/kickx/prototype';
type Client = Awaited<ReturnType<typeof authenticatedClient>>['client'];
/** Per-player frames ride along with the engagement state; an unapplied migration reads as none. */
async function withPlayerFrames(client: Client, data: unknown) {
 if (!data || typeof data !== 'object' || Array.isArray(data) || !('loadout' in data)) return data;
 const f = await client.rpc('kickx_player_frames');
 if (f.error && !migrationMissing(f.error)) checkDatabase(f.error);
 return { ...data, playerFrames: f.error ? {} : f.data ?? {}, playerFramesReady: !f.error };
}
export async function GET() {
 try { const { client } = await authenticatedClient(); const r = await client.rpc('kickx_engagement'); checkDatabase(r.error); return json({ status: 'ready', data: await withPlayerFrames(client, r.data) }); }
 catch (e) { return failure(e); }
}
export async function POST(request: Request) {
 try {
  requireOrigin(request);
  const { client } = await authenticatedClient(), body = asObject(await readJson(request));
  const action = body.action;
  if (typeof action !== 'string' || !['attendance','claim_daily','claim_weekly','claim_weekly_item','purchase','equip','player_frame','recover','view','draw','place_draw'].includes(action)) throw new HttpError(400, '요청을 확인해 주세요.');
  const input = body.input == null ? {} : asObject(body.input);
  let r;
  if (action === 'view') {
   if (!['fixtures','price','ai_report'].includes(String(input.kind)) || typeof input.target !== 'string' || input.target.length > 210) throw new HttpError(400,'활동 대상을 확인해 주세요.');
   r = await client.rpc('kickx_mission_view', { p_kind: input.kind, p_target: input.target });
  } else if (action === 'draw') r = await client.rpc('kickx_draw', { p_request: identity(input.requestId, true) });
  else if (action === 'place_draw') r = await client.rpc('kickx_place_draw', { p_draw: identity(input.drawId, true), p_bench: input.benchPlayer == null ? null : identity(input.benchPlayer) });
  else if (action === 'player_frame') {
   if (typeof input.playerId !== 'string' || input.playerId.length > 120 || (input.itemId != null && typeof input.itemId !== 'string')) throw new HttpError(400, '요청을 확인해 주세요.');
   const set = await client.rpc('kickx_set_player_frame', { p_player: input.playerId, p_item: input.itemId ?? null }); checkDatabase(set.error);
   r = await client.rpc('kickx_engagement');
  } else {
   if (action === 'claim_weekly_item' && (typeof input.mission !== 'string' || input.mission.length > 40)) throw new HttpError(400, '요청을 확인해 주세요.');
   r = await client.rpc('kickx_engagement_action', { p_action: action, p_input: input });
  }
  checkDatabase(r.error); return json(await withPlayerFrames(client, r.data));
 } catch (e) { return failure(e); }
}
