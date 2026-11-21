import test from "node:test";
import assert from "node:assert/strict";
import { loadTs } from "./load-ts.mjs";

const community = loadTs("../lib/kickx/community.ts", { "./validation": { POST_LIMITS: { titleMin: 2, titleMax: 80, bodyMin: 10, bodyMax: 3000 } } });
const slots = ["raya", "saliba", "", "gabriel", "white", "rice", "odegaard", "", "saka", "havertz", "martinelli"];

test("squad marker round-trips and keeps the body text separate", () => {
  const marker = community.squadMarker("4-3-3", slots);
  const { text, squad } = community.splitSquad("오늘 스쿼드 공유합니다." + marker);
  assert.equal(text, "오늘 스쿼드 공유합니다.");
  assert.deepEqual(squad, { formation: "4-3-3", slots });
  assert.equal(community.postTitle("", "본문 제목 대체" + marker), "본문 제목 대체");
});

test("invalid squads produce no marker", () => {
  assert.equal(community.squadMarker("4-3-3", slots.slice(0, 10)), null);
  assert.equal(community.squadMarker("4-3-3", [...slots.slice(0, 10), "bad,id"]), null);
  assert.equal(community.squadMarker("<b>", slots), null);
});

test("hand-typed or misplaced markers are stripped and never read as an attachment", () => {
  const typed = "가짜 [[kickx-squad:4-3-3:a,b,c,d,e,f,g,h,i,j,k]] 중간에 넣은 표시";
  assert.equal(community.splitSquad(typed).squad, null);
  assert.equal(community.stripSquadMarkers(typed).includes("kickx-squad"), false);
  const short = "본문입니다 열자 이상\n\n[[kickx-squad:4-3-3:a,b,c]]";
  assert.equal(community.splitSquad(short).squad, null);
});
