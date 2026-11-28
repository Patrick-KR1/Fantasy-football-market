import { connection } from 'next/server';
import { createPublicClient } from '@/server/kickx/supabase';
import { getSupabaseConfig } from '@/server/kickx/config';
import { emptyShop } from '@/lib/kickx/engagement';
import { checkDatabase } from '@/server/kickx/prototype';
import { failure } from '@/server/kickx/http';
export async function GET() {
 await connection();
 if (!getSupabaseConfig()) return Response.json({ status: 'not-configured', data: emptyShop() }, { headers: { 'Cache-Control': 'no-store' } });
 try {
  // The public catalog contains no inventory or account data. Do not refresh a
  // visitor's session/cookies for this cacheable anonymous read.
  const client = createPublicClient();
  const r = await client.rpc('kickx_shop_catalog'); checkDatabase(r.error);
  return Response.json({ status: 'ready', data: r.data }, { headers: { 'Cache-Control': 'public, max-age=30, s-maxage=30' } });
 } catch (e) { return failure(e); }
}
