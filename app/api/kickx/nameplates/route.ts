import { createRequestClient } from '@/server/kickx/supabase';
import { failure, HttpError, json } from '@/server/kickx/http';
import { checkDatabase } from '@/server/kickx/prototype';
export async function GET(request: Request) {
 try {
  const users = [...new Set((new URL(request.url).searchParams.get('users') ?? '').split(',').filter(Boolean))];
  if (users.length > 100 || users.some(id => !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(id))) throw new HttpError(400,'회원 ID를 확인해 주세요.');
  if (!users.length) return json({});
  const r = await (await createRequestClient()).rpc('kickx_nameplates', { p_users: users }); checkDatabase(r.error); return json(r.data);
 } catch (e) { return failure(e); }
}
