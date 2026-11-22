"use client";
import { useEffect, useId, useRef, useState, type CSSProperties } from "react";
import { ChevronRight, Minus, TrendingDown, TrendingUp, X } from "lucide-react";
import { cosmeticTheme } from "@/lib/kickx/engagement";
import { clubIdentity } from "@/lib/kickx/club-identity";
import { money } from "@/lib/kickx/data";
import {
  PRICE_REVEAL_PAGE_SIZE,
  priceRevealPage,
  priceRevealPlayers,
  priceRevealSignature,
} from "@/lib/kickx/price-reveal";
import type { Player } from "@/lib/kickx/types";
import { usePlatform } from "./provider";
import { useEngagement } from "./engagement-provider";
import { FramedPlayer } from "./player-frame";
import { Change, ClubCrest, PositionBadge } from "./ui";

const seenKey = (userId: string) => `kickx:price-seen:${userId}`;
function readSeen(userId: string): Record<string, string> {
  try {
    const raw = localStorage.getItem(seenKey(userId));
    const value = raw ? JSON.parse(raw) : {};
    return value && typeof value === "object" && !Array.isArray(value) ? value : {};
  } catch {
    return {};
  }
}
function writeSeen(userId: string, players: Player[]) {
  try {
    const seen = readSeen(userId);
    for (const player of players) seen[player.id] = priceRevealSignature(player);
    localStorage.setItem(seenKey(userId), JSON.stringify(seen));
  } catch { /* Storage unavailable: the reveal may play again next visit. */ }
}

/** Present up to six held players together, using a snapshot of server prices.
 * The squad's replay button remounts this component; preview leaves seen state untouched. */
export function PriceReveal({ playerIds, preview = false }: { playerIds: string[]; preview?: boolean }) {
  const { data, getPlayer, getTeam } = usePlatform();
  const { state } = useEngagement();
  const userId = data.session?.userId;
  const titleId = useId();
  const [queue, setQueue] = useState<Player[] | null>(null);
  const [pageIndex, setPageIndex] = useState(0);
  const closeRef = useRef<HTMLButtonElement>(null);
  const nextRef = useRef<HTMLButtonElement>(null);
  const gridRef = useRef<HTMLDivElement>(null);
  const pendingIds = (() => {
    if (!userId || typeof window === "undefined") return "";
    // Explicit replay works even when automatic reveals are switched off.
    if (!preview) {
      try {
        if (localStorage.getItem("kickx:price-reveal") === "off") return "";
      } catch { /* Storage unavailable. */ }
    }
    return priceRevealPlayers(playerIds, getPlayer, readSeen(userId), preview)
      .map((player) => player.id).join(",");
  })();

  useEffect(() => {
    if (queue || !pendingIds) return;
    const timer = setTimeout(() => {
      setQueue(pendingIds.split(",").map((id) => getPlayer(id)).filter((player): player is Player => !!player));
    }, preview ? 0 : 350);
    return () => clearTimeout(timer);
    // Snapshot only when opening; platform refreshes must not reorder an open page.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [pendingIds, queue, preview]);

  const pageCount = Math.ceil((queue?.length ?? 0) / PRICE_REVEAL_PAGE_SIZE);
  const open = !!userId && !!queue?.length && pageIndex < pageCount;
  useEffect(() => {
    if (!open) return;
    const previousFocus = document.activeElement instanceof HTMLElement ? document.activeElement : null;
    const previousOverflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    return () => {
      document.body.style.overflow = previousOverflow;
      if (previousFocus?.isConnected) previousFocus.focus({ preventScroll: true });
    };
  }, [open]);
  useEffect(() => {
    if (!open) return;
    nextRef.current?.focus({ preventScroll: true });
    if (gridRef.current) gridRef.current.scrollTop = 0;
  }, [open, pageIndex]);

  if (!open || !queue || !userId) return null;
  const players = priceRevealPage(queue, pageIndex);
  const last = pageIndex === pageCount - 1;
  const finish = () => {
    if (!preview) writeSeen(userId, queue);
    setPageIndex(pageCount);
  };
  const next = () => {
    if (last) finish();
    else {
      if (!preview) writeSeen(userId, players);
      setPageIndex((page) => page + 1);
    }
  };

  return (
    <div
      className="price-reveal"
      role="dialog"
      aria-modal="true"
      aria-labelledby={titleId}
      onKeyDown={(event) => {
        if (event.key === "Escape") { event.preventDefault(); finish(); }
        if (event.key === "Tab") {
          if (event.shiftKey && document.activeElement === closeRef.current) {
            event.preventDefault(); nextRef.current?.focus();
          } else if (!event.shiftKey && document.activeElement === nextRef.current) {
            event.preventDefault(); closeRef.current?.focus();
          }
        }
      }}
    >
      <div className="price-reveal-backdrop" onClick={finish} />
      <div className="price-reveal-stage" data-count={players.length}>
        <p className="price-reveal-kicker" id={titleId}>
          {preview ? "마지막 가치 변동 · 테스트" : "가격 변동 확인"}
          <span className="num">{pageIndex * PRICE_REVEAL_PAGE_SIZE + 1}–{Math.min((pageIndex + 1) * PRICE_REVEAL_PAGE_SIZE, queue.length)} / {queue.length}명</span>
        </p>
        <div className="price-reveal-grid" ref={gridRef} key={pageIndex}>
          {players.map((player) => {
            const known = player.change != null && Number.isFinite(player.change);
            const up = known && player.change! > 0;
            const down = known && player.change! < 0;
            const team = getTeam(player.team);
            const club = clubIdentity(team);
            return (
              <article
                className={`price-reveal-card ${up ? "is-up" : down ? "is-down" : "is-flat"}`}
                key={player.id}
                data-player-id={player.id}
                aria-label={`${player.name} 가치 변동`}
                style={club ? { "--club": club.primary } as CSSProperties : undefined}
              >
                <span className="price-reveal-rays" aria-hidden="true" />
                {(up || down) && <span className="price-reveal-arrows" aria-hidden="true">
                  {Array.from({ length: 7 }, (_, i) => <i key={i} style={{ "--i": i } as CSSProperties}>{up ? "▲" : "▼"}</i>)}
                </span>}
                <div className="price-reveal-face"><FramedPlayer player={player} theme={cosmeticTheme(state.playerFrames?.[player.id] ?? state.loadout?.frame)} preview /></div>
                <div className="price-reveal-id">{player.position && <PositionBadge position={player.position} />}<h2>{player.name}</h2></div>
                <div className="price-reveal-club">{player.team && <ClubCrest id={player.team} size="small" />}<span>{team?.name ?? "구단 정보 없음"}</span></div>
                <div className="price-reveal-value">
                  <span>{up ? <TrendingUp size={16} /> : down ? <TrendingDown size={16} /> : <Minus size={16} />}{up ? "가치 상승" : down ? "가치 하락" : known ? "변동 없음" : "변동 정보 없음"}</span>
                  <strong className="num">{money(player.price)}<small>P</small></strong>
                  <Change value={player.change} size="lg" />
                </div>
              </article>
            );
          })}
        </div>
        <div className="price-reveal-actions">
          <button type="button" ref={closeRef} className="button secondary small" onClick={finish}><X size={15} />{preview ? "닫기" : "모두 확인"}</button>
          <span className="price-reveal-pagination num" aria-live="polite">{pageIndex + 1} / {pageCount} 페이지</span>
          <button type="button" ref={nextRef} className="button small" onClick={next}>{last ? "확인" : <>다음 페이지<ChevronRight size={15} /></>}</button>
        </div>
      </div>
    </div>
  );
}
