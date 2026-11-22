"use client";
import { useId } from "react";
import { cosmeticTheme } from "@/lib/kickx/engagement";
import { useEngagement } from "./engagement-provider";
import { usePlatform } from "./provider";

/** Frame for one held player. "기본" follows the frame equipped for the whole squad. Ownership and the
    saved choice are checked by the server. */
export function PlayerFrameSelect({ playerId }: { playerId: string }) {
  const { notify } = usePlatform(), { state, ready, busy, act } = useEngagement();
  const id = useId();
  const owned = (state.catalog ?? []).filter((item) => item.category === "frame" && (state.inventory?.[item.id] ?? 0) > 0);
  if (!ready || !owned.length) return null;
  const current = state.playerFrames?.[playerId] ?? "";
  const fallback = owned.find((item) => item.id === state.loadout?.frame)?.name ?? "기본 테두리";
  async function change(itemId: string) {
    if (await act("player_frame", { playerId, itemId: itemId || null }))
      notify(itemId ? `${owned.find((item) => item.id === itemId)?.name ?? "테두리"}를 적용했습니다.` : "스쿼드 기본 테두리로 되돌렸습니다.");
  }
  return (
    <label className="player-frame-select" htmlFor={id}>
      <span>테두리</span>
      <select id={id} value={current} disabled={busy} data-theme={cosmeticTheme(current || state.loadout?.frame)} onChange={(e) => void change(e.target.value)}>
        <option value="">기본 · {fallback}</option>
        {owned.map((item) => <option key={item.id} value={item.id}>{item.name}</option>)}
      </select>
    </label>
  );
}
