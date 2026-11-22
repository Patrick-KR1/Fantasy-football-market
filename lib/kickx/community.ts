import { POST_LIMITS } from "./validation";
import type { Transaction } from "./types";
export type CommunityScope = "club" | "player";
export const COMMUNITY_PATHS = { club: "/community/clubs", player: "/community/players" } as const;

/** A squad attachment is a marker the server appends to the end of the body from the author's
    saved squad. Hand-typed markers are removed by the server, so a marker always reflects the
    author's own squad at the time of writing. */
export type SquadLook = { pitch: string | null; frames: (string | null)[] };
export type SquadAttachment = { formation: string; slots: string[]; look?: SquadLook };
const ITEM = /^(pitch|frame)-[a-z]{2,24}$/u;
const SQUAD_END = /\s*\[\[kickx-squad:([0-9]-[0-9](?:-[0-9]){1,3}):([A-Za-z0-9_.,-]{0,800})((?:\|[a-z]{1,8}=[a-z0-9,-]{0,400}){0,3})\]\]\s*$/u;
const SQUAD_ANY = /\[\[kickx-squad:[^\]]{0,1600}\]\]/gu;
export function stripSquadMarkers(body: string) { return body.replace(SQUAD_ANY, "").trimEnd(); }
export function splitSquad(body: string): { text: string; squad: SquadAttachment | null } {
  const match = body.match(SQUAD_END);
  const slots = match?.[2].split(",");
  if (!match || match.index == null || slots?.length !== 11) return { text: stripSquadMarkers(body), squad: null };
  const squad: SquadAttachment = { formation: match[1], slots };
  // Optional look recorded at posting time: |p=<pitch item>|f=<11 frame items, empty = none>
  const parts = Object.fromEntries((match[3] ?? "").split("|").filter(Boolean).map(part => part.split("=") as [string, string]));
  if (parts.p != null || parts.f != null) {
    const frames = (parts.f ?? "").split(",");
    squad.look = { pitch: ITEM.test(parts.p ?? "") ? parts.p : null, frames: frames.length === 11 ? frames.map(f => ITEM.test(f) ? f : null) : Array(11).fill(null) };
  }
  return { text: stripSquadMarkers(body.slice(0, match.index)), squad };
}
export function squadMarker(formation: string, slots: readonly (string | null)[], look?: { pitch?: string | null; frames?: readonly (string | null)[] }) {
  const ids = slots.map(id => id ?? "");
  if (!/^[0-9]-[0-9](?:-[0-9]){1,3}$/u.test(formation) || ids.length !== 11 || ids.some(id => !/^[A-Za-z0-9_.-]{0,64}$/u.test(id))) return null;
  let tail = "";
  if (look) {
    const pitch = look.pitch && ITEM.test(look.pitch) ? look.pitch : "";
    const frames = Array.from({ length: 11 }, (_, i) => { const f = look.frames?.[i]; return f && ITEM.test(f) ? f : ""; });
    tail = `|p=${pitch}|f=${frames.join(",")}`;
  }
  return `\n\n[[kickx-squad:${formation}:${ids.join(",")}${tail}]]`;
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
