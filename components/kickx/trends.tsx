"use client";
import type { Player, SeriesPoint } from "@/lib/kickx/types";
import { useResource } from "./provider";
import { Sparkline } from "./ui";

const DAY = 86400000;
const empty = () => ({} as Record<string, SeriesPoint[]>);

/** List pages carry no price history; fetch the 30-day series for the players on screen in one call. */
export function useTrends(players: Player[]) {
  const ids = [...new Set(players.filter((p) => !p.history?.length).map((p) => p.id))].slice(0, 60).sort().join(",");
  const { data } = useResource(ids ? `/api/kickx/players/trends?ids=${encodeURIComponent(ids)}` : null, empty, 0);
  return data;
}

/** Server values only: the stored points of the last 30 days (with the last earlier value as the start)
    and the current price as the final point when it is newer than the last stored one. */
export function trendValues(player: Player, series?: SeriesPoint[]) {
  const since = Date.now() - 30 * DAY;
  let points = player.history?.length ? player.history : series ?? [];
  if (player.history?.length) {
    const inside = points.filter((p) => Date.parse(p.at) >= since);
    const before = points.filter((p) => Date.parse(p.at) < since).at(-1);
    points = before ? [before, ...inside] : inside;
  }
  const values = points.map((p) => p.value).filter((v) => Number.isFinite(v));
  if (player.price != null && Number.isFinite(player.price) && values.at(-1) !== player.price) values.push(player.price);
  // A single known value means the price did not move in 30 days: draw it as a flat line.
  return values.length === 1 ? [values[0], values[0]] : values;
}

export function TrendSparkline({ player, series }: { player: Player; series?: SeriesPoint[] }) {
  const values = trendValues(player, series);
  return <Sparkline values={values} down={values.length > 1 ? values[values.length - 1] < values[0] : (player.change ?? 0) < 0} />;
}
