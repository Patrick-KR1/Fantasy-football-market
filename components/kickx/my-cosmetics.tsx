"use client";
import Link from "next/link";
import { useState } from "react";
import { Check, ShoppingBag } from "lucide-react";
import type { ShopItem } from "@/lib/kickx/engagement";
import { usePlatform } from "./provider";
import { useEngagement } from "./engagement-provider";
import { ShopPreview } from "./shop";
import { SectionTitle } from "./ui";

type Slot = "nameplate" | "frame" | "pitch";
const SLOTS: { id: Slot; label: string }[] = [{ id: "nameplate", label: "네임태그" }, { id: "frame", label: "선수 테두리" }, { id: "pitch", label: "경기장" }];

/** My page: owned cosmetics only, equip or take off. Ownership and the equipped state come from the server. */
export function MyCosmetics() {
  const { data, notify } = usePlatform(), { state, ready, busy, act } = useEngagement();
  const [slot, setSlot] = useState<Slot>("nameplate");
  const owned = (category: Slot) => (state.catalog ?? []).filter((item) => item.category === category && (state.inventory?.[item.id] ?? 0) > 0);
  const items = owned(slot), equippedId = state.loadout?.[slot] ?? null;
  async function equip(item: ShopItem | null) {
    const ok = await act("equip", { category: slot, itemId: item?.id ?? null });
    if (ok) notify(item ? `${item.name}을(를) 장착했습니다.` : "기본 디자인으로 되돌렸습니다.");
  }
  return (
    <section className="panel my-cosmetics" aria-label="보유한 꾸미기">
      <SectionTitle title="내 꾸미기" action={<Link href="/shop" className="text-link"><ShoppingBag size={14} />포인트 상점</Link>} />
      {!data.session ? <p className="muted">로그인 후 보유한 꾸미기를 장착할 수 있습니다.</p> : <>
        <div className="my-cosmetic-tabs" role="tablist" aria-label="꾸미기 종류">
          {SLOTS.map((s) => <button key={s.id} role="tab" aria-selected={slot === s.id} className={slot === s.id ? "active" : ""} onClick={() => setSlot(s.id)}>{s.label}<span className="num">{owned(s.id).length}</span></button>)}
        </div>
        {!ready ? <p className="muted">보유 정보를 확인하고 있습니다…</p> : !items.length ? (
          <div className="my-cosmetic-empty"><p>보유한 {SLOTS.find((s) => s.id === slot)?.label}이(가) 없습니다.</p><Link href={`/shop?category=${slot}`} className="button secondary small">상점에서 보기</Link></div>
        ) : (
          <div className="my-cosmetic-grid">
            {items.map((item) => {
              const on = equippedId === item.id;
              return <article key={item.id} className={`my-cosmetic${on ? " equipped" : ""}`}>
                <ShopPreview item={item} />
                <div className="my-cosmetic-info"><strong>{item.name}</strong>{on && <small><Check size={12} />장착 중</small>}</div>
                <button className={`button small ${on ? "secondary" : ""}`} disabled={busy} onClick={() => void equip(on ? null : item)}>{on ? "장착 해제" : "장착하기"}</button>
              </article>;
            })}
          </div>
        )}
        {ready && !!items.length && <p className="fine-print">장착을 해제하면 기본 디자인이 적용됩니다.{equippedId == null && " 지금은 기본 디자인을 사용하고 있습니다."}</p>}
      </>}
    </section>
  );
}
