import { createRequestClient } from "@/server/kickx/supabase";
import { getSupabaseConfig } from "@/server/kickx/config";
import { checkDatabase, migrationMissing } from "@/server/kickx/prototype";
import { failure, HttpError } from "@/server/kickx/http";

type Point = { at: string; value: number };
async function fromHistory(client: Awaited<ReturnType<typeof createRequestClient>>, ids: string[]) {
  const since = Date.now() - 30 * 86400000, out: Record<string, Point[]> = {};
  for (let i = 0; i < ids.length; i += 10) {
    const batch = ids.slice(i, i + 10);
    const results = await Promise.all(batch.map((id) => client.rpc("kickx_player_value_history", { p_player: id })));
    results.forEach((r, k) => {
      if (r.error || !Array.isArray(r.data)) return;
      const points = (r.data as Point[]).filter((p) => Number.isFinite(Date.parse(p.at)) && Number.isFinite(Number(p.value)));
      const daily = new Map<string, Point>();
      for (const p of points) if (Date.parse(p.at) >= since) daily.set(new Date(Date.parse(p.at) + 9 * 3600000).toISOString().slice(0, 10), p);
      const before = points.filter((p) => Date.parse(p.at) < since).at(-1);
      const series = [...(before ? [before] : []), ...daily.values()];
      if (series.length) out[batch[k]] = series;
    });
  }
  return out;
}

/** 30-day price trend for the players shown on a list page (at most 60 ids). Public data only. */
export async function GET(request: Request) {
  try {
    const raw = new URL(request.url).searchParams.get("ids") ?? "";
    const ids = [...new Set(raw.split(",").map((id) => id.trim()).filter(Boolean))];
    if (ids.length > 60 || ids.some((id) => !/^[A-Za-z0-9_.-]{1,64}$/.test(id))) throw new HttpError(400, "선수 목록을 확인해 주세요.");
    if (!ids.length || !getSupabaseConfig()) return Response.json({ status: "ready", data: {} });
    const client = await createRequestClient();
    const r = await client.rpc("kickx_player_trends", { p_players: ids });
    // Until the batch function is applied, build the same series from the existing per-player history.
    if (migrationMissing(r.error)) return Response.json({ status: "ready", data: await fromHistory(client, ids) }, { headers: { "Cache-Control": "public, max-age=60, s-maxage=60" } });
    checkDatabase(r.error);
    return Response.json({ status: "ready", data: r.data ?? {} }, { headers: { "Cache-Control": "public, max-age=60, s-maxage=60" } });
  } catch (error) { return failure(error); }
}
