import { POST_LIMITS } from "./validation";
import type { Transaction } from "./types";
export type CommunityScope = "club" | "player";
export const COMMUNITY_PATHS = { club: "/community/clubs", player: "/community/players" } as const;

/** A squad attachment is a marker the server appends to the end of the body from the author's
    saved squad. Hand-typed markers are removed by the server, so a marker always reflects the
    author's own squad at the time of writing. */
export type SquadAttachment = { formation: string; slots: string[] };
const SQUAD_END = /\s*\[\[kickx-squad:([0-9]-[0-9](?:-[0-9]){1,3}):([A-Za-z0-9_.,-]{0,800})\]\]\s*$/u;
const SQUAD_ANY = /\[\[kickx-squad:[^\]]{0,900}\]\]/gu;
export function stripSquadMarkers(body: string) { return body.replace(SQUAD_ANY, "").trimEnd(); }
export function splitSquad(body: string): { text: string; squad: SquadAttachment | null } {
  const match = body.match(SQUAD_END);
  const slots = match?.[2].split(",");
  if (!match || match.index == null || slots?.length !== 11) return { text: stripSquadMarkers(body), squad: null };
  return { text: stripSquadMarkers(body.slice(0, match.index)), squad: { formation: match[1], slots } };
}
export function squadMarker(formation: string, slots: readonly (string | null)[]) {
  const ids = slots.map(id => id ?? "");
  if (!/^[0-9]-[0-9](?:-[0-9]){1,3}$/u.test(formation) || ids.length !== 11 || ids.some(id => !/^[A-Za-z0-9_.-]{0,64}$/u.test(id))) return null;
  return `\n\n[[kickx-squad:${formation}:${ids.join(",")}]]`;
}

/** Display-only fallback for legacy posts. New writes must provide an explicit title. */
export function postTitle(title: string, body: string) {
  return title.normalize("NFC").trim() || [...splitSquad(body).text.normalize("NFC").trim().replace(/\s+/gu, " ")].slice(0, POST_LIMITS.titleMax).join("");
}
export function postHeading(title: string, body: string) {
  return postTitle(title, body);
}
/** A player lounge can attach only the current player's own trades. */
export function attachmentTrades(transactions: Transaction[], scope: CommunityScope, target: string) {
  return transactions.filter(t => scope === 'club' || t.playerId === target);
}
export function parseCommunityQuery(params: URLSearchParams) {
  const scope = params.get("scope") ?? "player";
  if (scope !== "club" && scope !== "player") throw new Error("커뮤니티 종류를 확인해 주세요.");
  const sort = params.get("sort") ?? "new";
  if (sort !== "new" && sort !== "popular") throw new Error("게시글 정렬을 확인해 주세요.");
  const rawPage = params.get("page") ?? "1";
  if (!/^\d+$/.test(rawPage) || Number(rawPage) < 1 || Number(rawPage) > 10000) throw new Error("페이지 범위를 확인해 주세요.");
  const target = params.get("target");
  if (target !== null && !/^[a-zA-Z0-9_-]{1,100}$/.test(target)) throw new Error("커뮤니티 대상을 확인해 주세요.");
  const query = (params.get("q") ?? "").normalize("NFC").trim();
  if (query.length > 100 || /[\x00-\x1f]/.test(query)) throw new Error("검색어는 100자 이내로 입력해 주세요.");
  return { scope: scope as CommunityScope, sort, page: Number(rawPage), target, query };
}
