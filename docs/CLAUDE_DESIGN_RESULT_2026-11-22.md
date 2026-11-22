# KICK-X 클로드 작업 결과: 사용자 요청 8건 (2026-11-22)

기준: `main` `319eb4f`. 이번 요청에는 정책 변경(게시 권한, 보상, 가격)이 들어 있어 DB 마이그레이션 4개를 추가했다. **운영 DB에는 적용하지 않았다.** 적용하기 전에는 해당 기능이 운영에서 동작하지 않는다(화면은 안전하게 비활성 또는 빈 값으로 처리).

## 변경 목록

| # | 요청 | 반영 | 파일 |
| --- | --- | --- | --- |
| 1 | 서브 응원 구단에도 글 작성 | 메인 응원 구단을 설정한 회원은 모든 응원 구단(메인+서브)에 게시글을 쓸 수 있다. 응원하지 않는 구단은 계속 막는다. 글쓰기 구단 선택, 안내 문구, 규칙 페이지, 프로필 안내를 함께 변경했다 | `20261122100000_supported_club_posting.sql`, `lib/kickx/support.ts`, `lib/kickx/validation.ts`, `community*.tsx`, `rules-report.tsx`, `auth.tsx` |
| 2 | 스쿼드 첨부에 당시 경기장·테두리·얼굴 | 서버가 글을 저장할 때 작성자의 장착 경기장과 선발 11명 각자의 테두리(개별 테두리가 없으면 장착 테두리)를 함께 기록한다. 첨부 카드와 미리보기는 유니폼 대신 선수 얼굴, 그 경기장 테마, 선수별 테두리로 그리고 현재 가치는 숨긴다. 예전 첨부는 기본 경기장으로 표시 | `lib/kickx/community.ts`, `app/api/kickx/community/route.ts`, `squad-attachment.tsx`, `squad.tsx`(`look`, `hideValues`) |
| 3 | 선수별 테두리 | 스쿼드에서 보유 선수를 누르면 `테두리` 선택이 나온다. `기본`은 장착 테두리를 따른다. 보유한 테두리만, 보유한 선수에게만 적용(서버 확인). 가격 변동 연출 카드도 선수별 테두리를 쓴다 | `20261122110000_…sql`(`player_frames`, `kickx_set_player_frame`, `kickx_player_frames`), `app/api/kickx/engagement/route.ts`, `player-frame-select.tsx`, `squad.tsx`, `price-reveal.tsx` |
| 4 | 리포트 가격 반영 문구 | 제목을 `이번 경기 가격 반영 근거`로 바꾸고 문장마다 줄을 나눴다. `현재 가격과 무관한 기준 단위로 계산합니다`를 삭제했다. 계산식은 그대로 | `lib/kickx/match-report.ts`, `match-report.tsx` |
| 5 | 뽑기 벤치 선택에 현재 가치 | 선택 목록의 각 선수(뽑은 선수 포함) 오른쪽에 현재 가치(서버 값)를 표시 | `draw.tsx` |
| 6 | 주간 미션 보상 | 미션별 완료 보상 1,000P(미션마다 따로 수령), 올 클리어 4,000P. 주간 최대치는 10,000P로 같다. 미션 행에 `+1,000 P` 수령 버튼과 `수령 완료` 표시 | `20261122110000_…sql`(`weekly_item_claims`, `claim_weekly_item`), `missions.tsx` |
| 7 | 출석 복구권 | 2,500P | `20261122110000_…sql` |
| 8 | 30일 추이 | (마이그레이션 적용 전에는 기존 선수별 이력 함수로 같은 값을 만들어 바로 동작) **원인:** 목록·홈 데이터에는 가격 이력이 들어 있지 않아(`history: []`) 항상 `—`로 표시됐다. 데이터 자체는 있었다(선수당 30일 동안 4–6개 기록). **수정:** 화면에 보이는 선수만 한 번에 조회하는 `kickx_player_trends`와 `/api/kickx/players/trends`를 추가했다. 한국 날짜별 마지막 값과 그 전의 마지막 값을 쓰고, 현재 가격이 더 최신이면 끝점으로 붙인다. 홈 시장 표, 선수 시장 목록·카드에 적용했고, 선 색은 30일 동안의 방향이다 | `20261122120000_player_trends.sql`, `app/api/kickx/players/trends/route.ts`, `trends.tsx`, `home.tsx`, `players.tsx`, `player-card.tsx` |

## 적용이 필요한 마이그레이션(순서대로)

1. `20261122100000_supported_club_posting.sql`: 서브 구단 게시 권한
2. `20261122110000_weekly_item_rewards_ticket_player_frames.sql`: 주간 미션 보상 1,000P×6 + 올 클리어 4,000P, 출석 복구권 2,500P, 선수별 테두리
3. `20261122120000_player_trends.sql`: 30일 추이 조회
4. (이전 회차 미적용분) `20261121090000_cosmetic_catalog_expansion.sql`: 치장 24종, 가격 확정 필요

2번은 이미 적용된 함수(`weekly_progress`, `kickx_engagement`, `kickx_engagement_action`)를 원문 치환으로 수정한다. 함수 모양이 예상과 다르면 예외를 내고 멈춘다.

## 검증

- `npm run lint` 통과, `npm test` 312/312, `npm run test:db` 44개 통과, `npm run build` 성공.
- 새로 추가하거나 바꾼 DB 검증:
  - 서브 구단 게시 허용, 응원하지 않는 구단 거부
  - 주간 미션별 보상 1회만 지급, 올 클리어 4,000P, 없는 미션 거부
  - 복구권 2,500P
  - 선수별 테두리: 보유 상품만, 보유 선수만, 해제
  - 30일 추이: 시작 값과 하루 마지막 값
- 단위 테스트: 스쿼드 첨부의 경기장·테두리 기록 왕복, 잘못된 값 거부, 예전 형식 읽기.
- 브라우저 테스트 12개 중 11개 통과(`browser-smoke`는 기존 환경 문제).
- 화면 확인(가짜 로그인 응답, 1440·390px):
  - 주간 미션 수령 버튼
  - 선수별 테두리 선택과 경기장 반영
  - 스쿼드 첨부 미리보기(얼굴, 우주 경기장, 선수별 테두리)
  - 홈 표 30일 추이
