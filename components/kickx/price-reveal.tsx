"use client";
import { useEffect, useRef, useState, type CSSProperties } from "react";
import { ChevronRight, TrendingDown, TrendingUp, X } from "lucide-react";
import { cosmeticTheme } from "@/lib/kickx/engagement";
import { clubIdentity } from "@/lib/kickx/club-identity";
import { money } from "@/lib/kickx/data";
import type { Player } from "@/lib/kickx/types";
import { usePlatform } from "./provider";
import { useEngagement } from "./engagement-provider";
import { FramedPlayer } from "./player-frame";
import { Change, ClubCrest, PositionBadge } from "./ui";

/** Which price update the member has already seen, per player (the server's price and change as a
    signature). Stored only in this browser: it decides whether to play the reveal, never what the price is. */
const signature = (p: Player) => `${p.price}|${p.change}`;
const seenKey = (userId: string) => `kickx:price-seen:${userId}`;
function readSeen(userId: string): Record<string, string> {
  try { const raw = localStorage.getItem(seenKey(userId)); const value = raw ? JSON.parse(raw) : {}; return value && typeof value === "object" ? value : {}; } catch { return {}; }
}
function writeSeen(userId: string, players: Player[]) {
  try { const seen = readSeen(userId); for (const p of players) seen[p.id] = signature(p); localStorage.setItem(seenKey(userId), JSON.stringify(seen)); } catch { /* storage unavailable: the reveal may play again */ }
}

/** Squad entry: dims the page and presents each held player whose price moved since the member last
    looked. Price and change are the server's values, shown as they are. */
export function PriceReveal({ playerIds }: { playerIds: string[] }) {
  const { data, getPlayer, getTeam } = usePlatform(), { state } = useEngagement();
  const userId = data.session?.userId;
  const [queue, setQueue] = useState<Player[] | null>(null), [index, setIndex] = useState(0);
  const nextRef = useRef<HTMLButtonElement>(null);
  // Ids whose current price update has not been seen yet (signature string keeps the effect stable).
  const pendingIds = (() => {
    if (!userId || typeof window === "undefined") return "";
    // Opt-out switch for automated browser checks (and anyone who prefers no reveal).
    try { if (localStorage.getItem("kickx:price-reveal") === "off") return ""; } catch { /* storage unavailable */ }
    const seen = readSeen(userId);
    return [...new Set(playerIds)].map((id) => getPlayer(id)).filter((p): p is Player =>
      !!p && p.price != null && p.change != null && Number.isFinite(p.change) && p.change !== 0 && seen[p.id] !== signature(p))
      // Largest moves first, so the most dramatic card opens the show.
      .sort((a, b) => Math.abs(b.change ?? 0) - Math.abs(a.change ?? 0)).map((p) => p.id).join(",");
  })();
  useEffect(() => {
    if (queue || !pendingIds) return;
    const timer = setTimeout(() => setQueue(pendingIds.split(",").map((id) => getPlayer(id)).filter((p): p is Player => !!p)), 350);
    return () => clearTimeout(timer);
    // getPlayer changes identity with platform data; pendingIds already captures what matters.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [pendingIds, queue]);
  const open = !!queue && index < queue.length;
  useEffect(() => {
    if (!open) return;
    nextRef.current?.focus();
    const previous = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    return () => { document.body.style.overflow = previous; };
  }, [open, index]);
  if (!open || !queue || !userId) return null;
  const player = queue[index], up = (player.change ?? 0) > 0, last = index === queue.length - 1;
  const team = getTeam(player.team), club = clubIdentity(team);
  const finish = () => { writeSeen(userId, queue); setIndex(queue.length); };
  const next = () => { writeSeen(userId, [player]); if (last) finish(); else setIndex(index + 1); };
  return (
    <div className={`price-reveal ${up ? "is-up" : "is-down"}`} role="dialog" aria-modal="true" aria-labelledby="price-reveal-title" onKeyDown={(e) => { if (e.key === "Escape") finish(); }}>
      <div className="price-reveal-backdrop" onClick={finish} />
      <div className="price-reveal-stage" key={player.id} style={club ? { "--club": club.primary } as CSSProperties : undefined}>
        <p className="price-reveal-kicker" id="price-reveal-title">가격 변동 확인 <span className="num">{index + 1} / {queue.length}</span></p>
        <article className="price-reveal-card">
          <span className="price-reveal-rays" aria-hidden="true" />
          <span className="price-reveal-arrows" aria-hidden="true">{Array.from({ length: 7 }, (_, i) => <i key={i} style={{ "--i": i } as CSSProperties}>{up ? "▲" : "▼"}</i>)}</span>
          <div className="price-reveal-face"><FramedPlayer player={player} theme={cosmeticTheme(state.loadout?.frame)} preview /></div>
          <div className="price-reveal-id">{player.position && <PositionBadge position={player.position} />}<h2>{player.name}</h2></div>
          <div className="price-reveal-club">{player.team && <ClubCrest id={player.team} size="small" />}<span>{team?.name ?? "구단 정보 없음"}</span></div>
          <div className="price-reveal-value">
            <span>{up ? <TrendingUp size={18} /> : <TrendingDown size={18} />}{up ? "가치 상승" : "가치 하락"}</span>
            <strong className="num">{money(player.price)}<small>P</small></strong>
            <Change value={player.change} size="lg" />
          </div>
        </article>
        <div className="price-reveal-actions">
          <button type="button" className="button secondary small" onClick={finish}><X size={15} />모두 확인</button>
          <button type="button" ref={nextRef} className="button small" onClick={next}>{last ? "확인" : <>다음 선수<ChevronRight size={15} /></>}</button>
        </div>
      </div>
    </div>
  );
}
