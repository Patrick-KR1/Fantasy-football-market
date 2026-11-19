import { createRequestClient } from '@/server/kickx/supabase';
import { checkDatabase } from '@/server/kickx/prototype';
import { failure } from '@/server/kickx/http';
export async function GET() {
 try {
  const client = await createRequestClient();
  const r = await client.rpc('kickx_shop_catalog'); checkDatabase(r.error);
  return Response.json({ status: 'ready', data: r.data }, { headers: { 'Cache-Control': 'public, max-age=30, s-maxage=30' } });
 } catch (e) { return failure(e); }
}
