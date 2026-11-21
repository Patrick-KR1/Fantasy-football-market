"use client";
import { Shirt } from "lucide-react";
import type { SquadAttachment } from "@/lib/kickx/community";
import { formationRule } from "@/lib/kickx/squad";
import { usePlatform } from "./provider";
import { Pitch } from "./squad";

/** Composer switch: the server attaches the author's saved squad; this only previews it. */
export function SquadAttachToggle({ checked, onChange, disabled }: { checked: boolean; onChange: (value: boolean) => void; disabled?: boolean }) {
  const { data } = usePlatform();
  const squad = data.member?.squad;
  const filled = squad?.slots.filter(Boolean).length ?? 0;
  const usable = !!squad && filled > 0;
  return (
    <div className={`squad-attach${checked ? " on" : ""}`}>
      <label className="squad-attach-switch">
        <input type="checkbox" checked={checked && usable} disabled={disabled || !usable} onChange={(e) => onChange(e.target.checked)} />
        <span><Shirt size={15} /><strong>내 스쿼드 첨부</strong><small>{usable ? `${formationRule(squad.formationId)?.name ?? squad.formationId} · 선발 ${filled}/11명 · 게시할 때의 스쿼드가 첨부됩니다` : "첨부할 스쿼드가 없습니다. 스쿼드를 먼저 구성해 주세요."}</small></span>
      </label>
      {checked && usable && <div className="squad-attach-preview" aria-label="첨부할 스쿼드 미리보기"><Pitch slots={squad.slots} formation={squad.formationId} compact /></div>}
    </div>
  );
}

/** Read-only squad card under a post body. */
export function SquadAttachmentCard({ squad, author }: { squad: SquadAttachment; author?: string }) {
  const rule = formationRule(squad.formation);
  return (
    <figure className="squad-attachment">
      <figcaption><Shirt size={15} /><strong>{author ? `${author}님의 스쿼드` : "작성자의 스쿼드"}</strong><span>{rule?.name ?? squad.formation} · 작성 당시</span></figcaption>
      <Pitch slots={squad.slots.map((id) => id || null)} formation={rule ? squad.formation : null} compact />
    </figure>
  );
}
