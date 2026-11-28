'use client';
import { useEffect, useRef, useState } from 'react';
import Link from 'next/link';
import { CalendarDays, Check, CheckCircle2, CircleHelp, Clock3, Gift, LockKeyhole, Minus, Target, Trophy, XCircle } from 'lucide-react';
import { apiRequest } from '@/lib/kickx/client';
import { money } from '@/lib/kickx/data';
import { emptyPredictions, predictionLabels, type PredictionChoice, type PredictionMatch, type Predictions } from '@/lib/kickx/predictions';
import { usePlatform, useResource } from './provider';
import { MemberNotice, PageHeading, TeamBadge } from './ui';

const kickoffDay = new Intl.DateTimeFormat('ko-KR', { timeZone: 'Asia/Seoul', year: 'numeric', month: '2-digit', day: '2-digit', weekday: 'short' });
const kickoffClock = new Intl.DateTimeFormat('ko-KR', { timeZone: 'Asia/Seoul', hour: '2-digit', minute: '2-digit', hourCycle: 'h23' });
function PredictionKickoff({ startsAt, status }: { startsAt: string; status: string }) {
 const date = new Date(startsAt);
 if (!Number.isFinite(date.getTime())) return <time className="prediction-kickoff">경기 일시 확인 중</time>;
 const day = kickoffDay.format(date), time = status === 'TBD' ? '시간 미정' : kickoffClock.format(date);
 return <time className="prediction-kickoff" dateTime={startsAt} aria-label={`${day} ${time} · 한국 시간`}>
  <span className="prediction-kickoff-date"><CalendarDays size={16} aria-hidden="true"/><strong>{day}</strong></span>
  <span className={`prediction-kickoff-time${status === 'TBD' ? ' unknown' : ''}`}><small>한국 시간</small><strong className="num">{time}</strong></span>
 </time>;
}

function MatchCard({ match, past, teamId, now, busy, onPick }: {
 match: PredictionMatch; past: boolean; teamId: string; now: number; busy: string | null;
 onPick: (match: PredictionMatch, choice: PredictionChoice) => Promise<void>;
}) {
 const open = match.canPredict && now < Date.parse(match.startsAt);
 const correct = match.choice != null && match.actual === match.choice;
 const settled = match.settledAt != null;
 const resultState = !match.choice ? 'no-pick' : settled ? correct ? 'success' : 'miss' : 'pending';
 const cardState = past ? resultState : !open ? 'closed' : match.choice ? 'picked' : 'unpicked';
 const ResultIcon = resultState === 'success' ? CheckCircle2 : resultState === 'miss' ? XCircle : resultState === 'pending' ? Clock3 : Minus;
 const StatusIcon = past ? Check : !open ? LockKeyhole : match.choice ? CheckCircle2 : Target;
 const statusLabel = past ? '경기 종료' : !open ? '예측 마감' : match.choice ? '예측 완료' : '예측 가능';
 return <article className={`prediction-card ${past ? 'past' : 'upcoming'} is-${cardState}`} id={`match-${match.id}`} aria-label={`${match.homeName} 대 ${match.awayName}`}>
  <header><span>{match.leagueName ?? '구단 경기'}</span><span className={`prediction-status ${cardState}`}><StatusIcon size={12} aria-hidden="true"/>{statusLabel}</span></header>
  <PredictionKickoff startsAt={match.startsAt} status={match.status}/>
  <div className="prediction-teams">
   <div className={match.homeId === teamId ? 'my-team' : ''}><TeamBadge id={match.homeId} size="large"/><strong>{match.homeName}</strong><small>홈{match.homeId === teamId ? ' · 내 구단' : ''}</small></div>
   <div className="prediction-score">{past && match.homeScore != null && match.awayScore != null ? <><strong className="num">{match.homeScore} : {match.awayScore}</strong>{match.status === 'PEN' && match.penaltiesHome != null && match.penaltiesAway != null && <small>승부차기 {match.penaltiesHome} : {match.penaltiesAway}</small>}</> : <strong>VS</strong>}</div>
   <div className={match.awayId === teamId ? 'my-team' : ''}><TeamBadge id={match.awayId} size="large"/><strong>{match.awayName}</strong><small>원정{match.awayId === teamId ? ' · 내 구단' : ''}</small></div>
  </div>
  {past ? <div className={`prediction-result ${resultState}`}>
   <div className="prediction-result-heading"><ResultIcon size={23} aria-hidden="true"/><div><span>{match.actual ? `경기 결과 · ${predictionLabels[match.actual]}` : '경기 결과 확인 중'}</span><strong>{!match.choice ? '미참여' : settled ? `예측 ${correct ? '성공' : '실패'}` : '보상 지급 대기'}</strong></div></div>
   <p>{match.choice ? <>내 예측 <b className={`prediction-choice ${match.choice}`}>{predictionLabels[match.choice]}</b>{settled ? <span className="num">+{money(match.reward)} P 지급 완료</span> : <span>결과 확인 후 자동 지급</span>}</> : '경기 시작 전에 예측하면 보상을 받을 수 있어요.'}</p>
  </div> : <div className="prediction-pick">
   <div className="prediction-pick-heading"><span>내 구단의 결과를 예측하세요</span>{match.choice ? <strong className={`prediction-choice ${match.choice}`}><Check size={12} aria-hidden="true"/>내 선택 · {predictionLabels[match.choice]}</strong> : <strong className="prediction-not-picked">아직 선택하지 않았어요</strong>}</div>
   <div className="prediction-options" role="group" aria-label={`${match.homeName} 대 ${match.awayName} 승부 예측`}>
    {(['win', 'draw', 'loss'] as const).map(choice => {
     const label = choice === 'win' ? '승리' : choice === 'draw' ? '무승부' : '패배';
     return <button type="button" key={choice} aria-label={`${predictionLabels[choice]} ${label}`} aria-pressed={match.choice === choice} disabled={!open || busy != null} onClick={() => void onPick(match, choice)} className={`prediction-option ${choice}${match.choice === choice ? ' selected' : ''}`}>
      {match.choice === choice && <Check size={15} aria-hidden="true"/>}<span>{predictionLabels[choice]}</span><small>{label}</small>
     </button>;
    })}
   </div>
   <p className={match.choice ? 'has-pick' : ''}>{busy === match.id ? '예측을 저장하고 있습니다…' : open ? match.choice ? <><CheckCircle2 size={13}/>선택이 저장됐어요. 시작 전까지 변경할 수 있어요.</> : <><Target size={13}/>승·무·패 버튼을 눌러 예측에 참여하세요.</> : <><LockKeyhole size={13}/>예측 마감 · 경기 결과를 기다려 주세요.</>}</p>
  </div>}
 </article>;
}

export function PredictionsScreen() {
 const { data, mock, notify, status } = usePlatform();
 const profile = data.session?.profile, userId = data.session?.userId;
 const remote = useResource(profile && userId && !mock ? `/api/kickx/predictions?member=${encodeURIComponent(userId)}` : null, emptyPredictions, 30000);
 const currentUser = useRef(userId); currentUser.current = userId;
 const [busy, setBusy] = useState<string | null>(null), [now, setNow] = useState(() => Date.now());
 useEffect(() => {
  const received = Date.now(), server = remote.data.serverTime ? Date.parse(remote.data.serverTime) : received;
  const tick = () => setNow(server + Date.now() - received);
  tick(); const timer = setInterval(tick, 1000); return () => clearInterval(timer);
 }, [remote.data.serverTime]);
 async function pick(match: PredictionMatch, choice: PredictionChoice) {
  if (busy) return;
  const owner = userId;
  setBusy(match.id);
  try {
   const result = await apiRequest<Predictions>('/api/kickx/predictions', 'POST', { fixtureId: match.id, choice });
   if (currentUser.current !== owner) return;
   remote.setData(result); notify(`${predictionLabels[choice]} 예측을 저장했습니다.`);
  } catch (error) { if (currentUser.current === owner) { notify(error instanceof Error ? error.message : '예측을 저장하지 못했습니다.', 'error'); remote.reload(); } }
  finally { setBusy(null); }
 }
 const ready = remote.status === 'ready', teamId = remote.data.teamId;
 return <>
  <PageHeading eyebrow="YOUR CLUB. YOUR CALL." title="경기 예측" description="내 메인 응원 구단의 다음 승부를 맞혀 보세요."/>
  <section className="prediction-hero">
   <div className="prediction-hero-copy"><span className="prediction-kicker"><Target size={17}/>MATCH PREDICTION</span><h2>승부를 읽고,<br/><em>포인트를 받으세요.</em></h2><p>승·무·패 중 하나를 선택하면 준비 끝.<br/>경기가 끝나면 결과와 보상을 알림함으로 보내 드려요.</p></div>
   <div className="prediction-rewards"><div className="reward-success"><Trophy size={21}/><span>예측 성공</span><strong className="num">5,000<small>P</small></strong></div><div className="reward-miss"><Gift size={21}/><span>예측 실패</span><strong className="num">1,000<small>P</small></strong></div><p>참여 비용 없이 · 예측 참여자에게 자동 지급</p></div>
  </section>
  {!profile ? <><MemberNotice/>{status === 'ready' && data.session && <div className="data-notice">프로필에서 메인 응원 구단을 먼저 설정해 주세요.<Link className="text-link" href="/mypage">프로필 설정</Link></div>}</> : !profile.primaryTeam ? <div className="data-notice">메인 응원 구단을 먼저 설정해 주세요.<Link className="text-link" href="/mypage">프로필 설정</Link></div> : mock ? <div className="data-notice">로그인 후 실제 구단 경기의 승부를 예측할 수 있습니다.</div> : !ready ? <div className="prediction-notice" role="status">{remote.status === 'loading' ? '메인 응원 구단의 경기를 불러오고 있습니다…' : remote.status === 'unauthorized' ? <Link href="/login">로그인 후 경기 예측을 이용해 주세요.</Link> : <>경기를 불러오지 못했습니다.<button className="button secondary small" onClick={remote.reload}>다시 시도</button></>}</div> : teamId && <>
   <div className="prediction-club"><div><TeamBadge id={teamId}/><span><small>내 메인 응원 구단</small><strong>{remote.data.teamName}</strong></span></div></div>
   <section className="prediction-section" aria-labelledby="upcoming-predictions"><header><div><span className="prediction-kicker">MAKE YOUR PICK</span><h2 id="upcoming-predictions">다가오는 3경기</h2></div><p>버튼을 누르면 저장 · 경기 시작 시 마감</p></header>
    {remote.data.upcoming.length ? <div className="prediction-grid">{remote.data.upcoming.map(match => <MatchCard key={match.id} match={match} past={false} teamId={teamId} now={now} busy={busy} onPick={pick}/>)}</div> : <div className="prediction-empty">등록된 다음 경기 일정이 없습니다. 일정이 확인되면 표시됩니다.</div>}
   </section>
   <section className="prediction-section" aria-labelledby="past-predictions"><header><div><span className="prediction-kicker">THE FINAL WHISTLE</span><h2 id="past-predictions">지난 3경기</h2></div><p>경기 결과와 나의 예측을 확인하세요.</p></header>
    {remote.data.past.length ? <div className="prediction-grid">{remote.data.past.map(match => <MatchCard key={match.id} match={match} past teamId={teamId} now={now} busy={busy} onPick={pick}/>)}</div> : <div className="prediction-empty">아직 종료된 경기 기록이 없습니다.</div>}
   </section>
   {remote.stale && <p className="prediction-notice" role="status">최신 경기 정보를 갱신하지 못했습니다. 잠시 후 다시 확인해 주세요.<button className="text-link" onClick={remote.reload}>다시 시도</button></p>}
  </>}
  <aside className="prediction-rules"><h3><CircleHelp size={17}/>경기 예측 안내</h3><ul><li>모든 예측과 경기 결과는 메인 응원 구단 기준입니다. 연장·승부차기가 있는 경기는 최종 결과를 따릅니다.</li><li>다가오는 3경기에 무료로 참여하며, 경기 시작 전까지 선택을 바꿀 수 있습니다. 미참여 경기에는 보상이 지급되지 않습니다.</li><li>경기 종료와 결과가 확인되면 성공 5,000P · 실패 1,000P가 자동 지급되고 알림함에 안내됩니다. 기록 제공이 늦으면 지급도 지연될 수 있습니다.</li><li>종료된 경기는 지난 3경기로 이동하고 다음 일정이 추가됩니다. 취소·연기된 경기는 예측 대상에서 제외되며, 연기 후 일정이 재등록되면 다시 표시됩니다.</li></ul></aside>
 </>;
}
