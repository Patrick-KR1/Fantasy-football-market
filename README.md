# KICK-X

**실제 축구 경기 데이터로 선수 가치를 평가하고, 가상 포인트로 나만의 스쿼드를 운용하는 축구 시뮬레이션 게임입니다.**

유럽 5대 리그 선수의 경기 기록과 가치 변동을 분석하고 자산 운용 성과를 비교할 수 있습니다. 선수·구단 커뮤니티에서는 경기와 선수에 관한 의견을 나눌 수 있습니다.

[웹 서비스](https://fantasy-football-market.vercel.app) · [팀 저장소](https://github.com/Patrick-KR1/Fantasy-football-market)

## 주요 기능

| 기능 | 설명 |
| --- | --- |
| 선수 시장 | 선수·구단·리그 검색, 포지션 필터, 정렬, 카드형·표형 목록, 관심 선수 등록 |
| 선수 분석 | 선수 기본정보, 경기 기록, Performance 산정 내역, 가치 변동 차트, 경기 리포트 |
| 선수 매입·매각 | 시스템 기준가격에 따른 즉시 체결, 견적 확인, 수수료·정원·경기 전후 제한 검사 |
| 스쿼드 | 19종 포메이션, 주전 배치·교환, 포지션별 선수 탐색, 벤치 이동·주전 복귀 |
| 자산·랭킹 | 보유 포인트, 선수 평가액, 평가손익, 자산 흐름, 거래 내역, 주간·월간 랭킹 |
| 커뮤니티 | 선수·구단 게시판, 게시글·댓글·답글, 공감·투표, 보유 인증, 본인 매입·매각 내역 첨부 |
| 계정·알림 | Google 로그인, 프로필·응원 구단 설정, 가격 변동·경기·댓글·답글 알림 |
| 운영 | 회원 이용 제한, 신고·게시물·거래 내역 관리, 경기 데이터 수집 및 점수·가치 자동 갱신 |

## 게임 방식

1. Google 계정으로 가입하면 초기 가상 포인트 **1,300,000P**가 지급됩니다.
2. 선수의 경기 기록과 가치 변동을 확인하고 현재 포메이션의 빈자리에 맞춰 선수를 영입합니다.
3. 실제 경기 기록을 포지션별 배점으로 계산해 Performance를 산정하고 선수 가치에 반영합니다.
4. 선수 구성과 매입·매각 시점을 조정하고 자산 변화와 기간별 랭킹을 확인합니다.

회원은 시스템이 제시하는 가격으로 선수를 매입·매각합니다. 다른 회원의 주문이나 매물을 기다릴 필요가 없으며, 여러 회원이 같은 선수를 각각 보유할 수 있습니다.

### 주요 규칙

- 주전은 최대 11명이며 포메이션별 GK·DF·MF·FW 정원을 적용합니다. 같은 선수를 중복 보유할 수 없습니다.
- 포메이션 변경 시 새 정원을 초과하는 포지션에서 벤치로 이동할 선수를 선택합니다. 나머지 주전은 유지됩니다.
- 벤치 선수도 현재 시세로 평가하며 전체 보유 자산에 포함됩니다. 벤치 이동 후 **7일 이내**에 조건을 충족하면 주전으로 복귀할 수 있습니다.
- 기한 내 복귀하거나 직접 매각하지 않은 벤치 선수는 자동 매각 대상이 됩니다. 경기 제한 중에는 제한 해제 후 정산합니다.
- 매입 수수료는 없으며 매각 수수료는 **2%**입니다.
- 경기 시작 **90분 전부터 종료 확인 후 10분까지** 해당 선수의 매입·매각을 제한합니다.
- 가격 반영은 지원하는 5대 정규 리그 경기를 대상으로 하며 취소된 경기는 산정에서 제외합니다.
- 단일 경기의 가격 변동은 직전 가격 대비 **±10%**, 최저 가격은 **10,000P**를 적용합니다. Performance 점수에는 10점 상한을 두지 않습니다.

KICK-X는 서비스 내부 가상 포인트를 사용합니다. 실제 금전 거래·환전·스포츠 베팅 기능을 제공하지 않습니다.

## 기술 스택

| 구분 | 기술 |
| --- | --- |
| 웹 애플리케이션 | Next.js 16, React 19, TypeScript |
| UI | Tailwind CSS, Radix UI, Lucide |
| 데이터베이스 | Supabase PostgreSQL, RLS, SQL 함수·트리거 |
| 인증 | Supabase Auth, Google OAuth |
| 축구 데이터 | BSD Football API |
| 경기 리포트 | Gemini API, 동일 입력의 저장 설명 재사용 |
| 배포·자동화 | Vercel, GitHub Actions, 예약 작업 |
| 검증 | Node.js Test Runner, ESLint, PostgreSQL·PGlite, Playwright |

## 로컬 실행

### 준비 사항

- Node.js **22 이상** 및 npm
- 실제 데이터와 로그인을 사용할 경우 Supabase 프로젝트와 Google OAuth 설정
- 데이터 수집을 실행할 경우 BSD API 키

### 설치

```sh
git clone https://github.com/Patrick-KR1/Fantasy-football-market.git
cd Fantasy-football-market
npm ci
```

`.env.example`을 복사해 `.env.local`을 만듭니다.

```sh
# macOS / Linux
cp .env.example .env.local
```

```powershell
# Windows PowerShell
Copy-Item .env.example .env.local
```

환경 설정 후 개발 서버를 실행합니다.

```sh
npm run dev
```

브라우저에서 [http://localhost:3000](http://localhost:3000)을 엽니다.

### 환경변수

| 변수 | 용도 |
| --- | --- |
| `NEXT_PUBLIC_SUPABASE_URL` | 웹 애플리케이션에서 사용할 Supabase URL |
| `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` | 클라이언트용 publishable 키. 기존 anon 키도 사용 가능 |
| `KICKX_DATABASE_ENABLED` | DB 및 로그인 설정 완료 후 `true`로 변경 |
| `KICKX_MOCK_DATA` | DB 연결 없이 화면을 확인하는 예시 데이터 모드 |
| `SUPABASE_URL` | 데이터 수집·자동 작업에서 사용할 Supabase URL |
| `SUPABASE_SERVICE_ROLE_KEY` | 데이터 수집·자동 작업의 서버 전용 키 |
| `BSD_API_KEY` | 축구 데이터 수집용 API 키 |
| `GEMINI_API_KEY` | 경기 리포트 설명 생성용 서버 전용 키 |
| `GEMINI_REPORT_MODEL` | 리포트 생성 모델 이름. 기본값은 `.env.example` 참고 |

`SUPABASE_SERVICE_ROLE_KEY`, `BSD_API_KEY`, `GEMINI_API_KEY`는 서버 환경에만 설정합니다. `.env.local`과 실제 비밀키는 Git에 커밋하지 않습니다.

### Supabase 설정

1. 새 Supabase 프로젝트를 생성합니다.
2. `supabase/migrations/`의 SQL을 **파일명 오름차순으로 한 번씩** 적용합니다. 기존 운영 DB에는 이미 적용한 마이그레이션을 반복 실행하지 않습니다.
3. Supabase Authentication에서 Google 공급자를 활성화하고 OAuth Client ID와 Secret을 설정합니다.
4. Google OAuth의 승인된 리디렉션 URI에 해당 프로젝트의 `https://<project-ref>.supabase.co/auth/v1/callback`을 등록합니다.
5. Supabase의 Site URL을 사용할 웹 주소로 설정하고 Redirect URLs에 `http://localhost:3000/auth/callback`과 실제 배포 주소의 `/auth/callback`을 등록합니다.
6. `.env.local`에 Supabase URL과 클라이언트용 키를 입력하고 `KICKX_DATABASE_ENABLED=true`로 설정합니다.

테이블 구조 적용과 실제 축구 데이터 적재는 별도 작업입니다. `tests/database-bootstrap.sql`은 격리된 시험 DB를 위한 파일이므로 실제 Supabase 프로젝트에 실행하지 않습니다.

```sh
npm run connection:check
```

### 예시 데이터로 화면 확인

DB 연결을 설정하기 전에는 아래 값으로 화면을 확인할 수 있습니다.

```dotenv
KICKX_DATABASE_ENABLED=false
KICKX_MOCK_DATA=true
```

예시 모드에서는 화면에 예시 데이터임을 표시합니다. 선수·가격·잔액은 시연용이며 변경 내용은 실제 DB에 저장되지 않습니다. DB 연결을 활성화하면 예시 데이터 모드는 적용되지 않습니다.

## 데이터 갱신과 경기 리포트

- 경기 일정·선수·구단 정보를 수집하고 종료 경기의 기록을 확인합니다.
- 기록이 변경된 선수의 Performance와 가격을 계산하며 동일 결과의 중복 반영을 방지합니다.
- 자산·랭킹·알림과 벤치 만료 처리를 자동 작업에 연결합니다.
- 경기 리포트는 경기 수치와 산정 결과를 바탕으로 설명을 제공합니다. 같은 입력의 저장된 설명을 재사용해 중복 생성을 줄입니다.
- AI 키가 없는 환경에서도 정형 경기 수치는 확인할 수 있습니다. 외부 데이터 반영 시점은 제공업체의 갱신과 예약 작업의 실행 시점에 영향을 받습니다.

GitHub Actions 자동 수집을 사용할 경우 저장소의 Actions Secrets에 `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `BSD_API_KEY`를 등록합니다. 워크플로는 `.github/workflows/football-automation.yml`에 있습니다.

## 주요 명령

| 명령 | 설명 |
| --- | --- |
| `npm run dev` | 개발 서버 실행 |
| `npm run build` | 배포용 빌드 및 타입 검사 |
| `npm start` | 빌드된 애플리케이션 실행 |
| `npm run lint` | ESLint 검사 |
| `npm test` | 단위 테스트 |
| `npm run test:db` | 격리된 PGlite DB에서 마이그레이션·DB 동작 검사 |
| `npm run connection:check` | Supabase 연결 설정 점검 |
| `npm run data:sync -- <인자>` | BSD 데이터 단건 수집 |
| `npm run data:sync:all -- <인자>` | BSD 데이터 일괄 수집·재개 |
| `npm run data:automatic` | 실제 연결된 DB의 수집·산정·운영 작업 실행 |

데이터 수집·자동 작업 명령은 연결한 DB를 갱신합니다. 수집 범위와 실행 옵션은 [수동 수집 안내](docs/manual-refresh.md)와 각 스크립트의 사용법을 확인합니다.

## 프로젝트 구조

| 경로 | 역할 |
| --- | --- |
| `app/` | 페이지, API Route Handler, OAuth 콜백 |
| `components/kickx/` | 화면·모달·차트·스쿼드 등 UI 컴포넌트 |
| `lib/kickx/` | 타입, 입력 검증, 포메이션, 클라이언트 API |
| `server/kickx/` | 인증, 데이터 조회·변경, 외부 API 연동 |
| `server/kickx/engine/` | Performance 및 선수 가치 산정 |
| `supabase/migrations/` | 테이블, 뷰, 함수, 트리거, RLS 정책 |
| `scripts/` | 데이터 수집·자동 처리·점검 도구 |
| `tests/` | 단위·DB·브라우저 검사 |
| `public/` | 이미지, 아이콘, 글꼴 |
| `.github/workflows/` | CI 및 데이터 처리 자동화 |
| `docs/` | 기능별 설계·운영·검증 자료 |

## 개발팀

대진대학교 컴퓨터공학전공 졸업작품

- 김승현
- 소윤섭
- 오정환

## 외부 자료

- 축구 데이터: BSD Football API
- 글꼴: Noto Sans KR — [SIL Open Font License](public/fonts/OFL-NotoSansKR.txt)

선수 사진·구단 엠블럼 등 외부 자료의 권리는 각 권리자에게 있습니다.
