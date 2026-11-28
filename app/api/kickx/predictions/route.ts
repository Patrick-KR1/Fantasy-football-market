import { authenticatedClient, failure, HttpError, json, readJson, requireOrigin } from '@/server/kickx/http';
import { asObject, checkDatabase, identity } from '@/server/kickx/prototype';
export async function GET() {
 try {
  const { client } = await authenticatedClient(), result = await client.rpc('kickx_predictions');
  checkDatabase(result.error);
  return json({ status: 'ready', data: result.data });
 } catch (error) { return failure(error); }
}
export async function POST(request: Request) {
 try {
  requireOrigin(request);
  const { client } = await authenticatedClient(), body = asObject(await readJson(request));
  if (typeof body.choice !== 'string' || !['win', 'draw', 'loss'].includes(body.choice)) throw new HttpError(400, '승·무·패 중 하나를 선택해 주세요.');
  const result = await client.rpc('kickx_predict', { p_fixture: identity(body.fixtureId), p_choice: body.choice });
  checkDatabase(result.error);
  return json(result.data);
 } catch (error) { return failure(error); }
}
