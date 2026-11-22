"use client";
import { useEffect } from "react";
import Link from 'next/link';
import { CalendarCheck, Check, CheckCircle2, Gift, RotateCcw, ArrowUpRight } from 'lucide-react';
import { MISSION_LABELS, MISSION_LINKS, weekDays, type Mission } from '@/lib/kickx/engagement';
import { money } from '@/lib/kickx/data';
import { useEngagement } from './engagement-provider';
import { usePlatform } from './provider';
import { MemberNotice, PageHeading } from './ui';
export function EngagementNotice() {
 const { data }=usePlatform(),{ready,error,reload}=useEngagement();
 if(!data.session?.profile)return <MemberNotice/>;
 return !ready?<div className="eng-notice" role="status">{error?'미션·상점 정보를 불러오지 못했습니다.':'미션·상점 정보를 불러오는 중…'}{error&&<button className="button secondary small" onClick={reload}>다시 시도</button>}</div>:null;
}
/** Weekly rows carry their own 1,000P claim; the reward amount comes from the server state. */
function MissionRow({mission,weekly=false,claim}:{mission:Mission;weekly?:boolean;claim?:{reward:number;claimed:boolean;disabled:boolean;onClaim:()=>void}}) {
 const complete=mission.current>=mission.target;
 const label=mission.id==='attendance'&&weekly?'주간 출석 7일':MISSION_LABELS[mission.id]??mission.id;
 return <li className={`mission-row ${complete?'is-complete':''}`}>
  <span className="mission-check" aria-hidden="true">{complete?<Check size={17}/>:<span/>}</span>
  <div className="mission-info"><strong>{label}</strong><div className="mission-progress" role="progressbar" aria-label={label} aria-valuemin={0} aria-valuemax={mission.target} aria-valuenow={Math.min(mission.current,mission.target)}><i style={{width:`${Math.min(100,mission.current/mission.target*100)}%`}}/></div></div>
  <span className="mission-count num">{Math.min(mission.current,mission.target)}<small> / {mission.target}</small></span>
  {complete&&claim?(claim.claimed?<span className="mission-done">수령 완료</span>:<button type="button" className="button small mission-claim" disabled={claim.disabled} onClick={claim.onClaim}>+{money(claim.reward)} P</button>):complete?<span className="mission-done">완료</span>:mission.id==='attendance'&&!weekly?<span className="mission-auto-attendance">방문 시 자동</span>:MISSION_LINKS[mission.id]?<Link className="mission-go" href={MISSION_LINKS[mission.id]} aria-label={`${label} 하러 가기`}><ArrowUpRight size={18}/></Link>:<span className="mission-go"/>}
 </li>;
}
export function MissionsScreen() {
 const {state,ready,busy,act,reload}=useEngagement(),{data}=usePlatform();
 useEffect(reload,[reload]);
 const weeklyComplete=state.weekly.items.length===6&&state.weekly.items.every(m=>m.current>=m.target);
 const days=weekDays(state.weekly.week),tickets=state.inventory['attendance-ticket']??0;
 async function action(name:string,input?:Record<string,unknown>){await act(name,input);}
 return <>
  <PageHeading eyebrow="SMALL STEPS. BIG REWARDS." title="미션" description="매일 세 가지, 매주 여섯 가지. 축구를 즐기며 포인트를 모으세요." action={<Link className="button secondary" href="/shop">포인트 상점 <ArrowUpRight size={16}/></Link>}/>
  <EngagementNotice/>
  <div className="eng-hero mission-hero"><div><span className="eng-kicker">YOUR NEXT KICK</span><h2>오늘의 참여가<br/><em>다음 영입으로.</em></h2><p>사이트에 방문하면 자동 출석, 나머지는 무작위 두 가지.<br/>모든 미션을 끝내면 보상이 열립니다.</p></div><div className="mission-hero-rewards"><div><span>일일 올 클리어</span><strong className="num">1,000<small>P</small></strong></div><span className="mission-hero-plus">+</span><div><span>주간 미션당 · 올 클리어</span><strong className="num">{money(state.weekly.itemReward??1000)}<small>P</small> · {money(state.weekly.reward)}<small>P</small></strong></div></div></div>
  <div className="missions-grid">
   <section className="mission-panel"><header><div><span className="eng-kicker">DAILY CHALLENGE</span><h2>일일 미션</h2></div><span className="eng-reset">매일 00:00 초기화 · 한국 시간</span></header>
    <ul>{state.daily.items.map(m=><MissionRow key={m.id} mission={m}/>)}</ul>
    <footer><div><Gift size={21}/><span>모두 완료하면 <strong className="num">1,000 P</strong></span></div><button className="button" disabled={!ready||busy||!state.daily.cleared||state.daily.claimed} onClick={()=>void action('claim_daily')}>{state.daily.claimed?'보상 수령 완료':'보상 받기'}</button></footer>
   </section>
   <section className="mission-panel weekly"><header><div><span className="eng-kicker">WEEKLY CHALLENGE</span><h2>주간 미션 <small className="eng-mode">{state.weekly.international?'A매치 주간':'정규리그 주간'}</small></h2></div><span className="eng-reset">매주 화요일 00:00 초기화 · 한국 시간</span></header>
    {ready&&<p className="mission-mode-note">{state.weekly.international?'금~월 5대 정규리그 경기가 없어 경기 기반 미션을 조회 미션으로 대체했습니다.':'금~월 5대 정규리그 경기가 있어 출전·Performance 미션을 진행합니다.'}</p>}
    <ul>{state.weekly.items.map(m=><MissionRow key={m.id} mission={m} weekly claim={{reward:state.weekly.itemReward??1000,claimed:(state.weekly.claimedItems??[]).includes(m.id),disabled:!ready||busy,onClaim:()=>void action('claim_weekly_item',{mission:m.id})}}/>)}</ul>
    <footer><div><Gift size={21}/><span className="weekly-reward-text">미션별 <b className="num">{money(state.weekly.itemReward??1000)} P</b> · 올 클리어 <b className="num">+{money(state.weekly.reward)} P</b></span></div><button className="button" disabled={!ready||busy||!weeklyComplete||state.weekly.claimed} onClick={()=>void action('claim_weekly')}>{state.weekly.claimed?'보상 수령 완료':'올 클리어 보상 받기'}</button></footer>
   </section>
  </div>
  <section className="attendance-panel"><header><div><CalendarCheck size={24}/><div><h2>이번 주 출석</h2><p>화요일부터 월요일까지, 일곱 칸을 채우세요.</p></div></div><Link href="/shop?category=ticket" className="button secondary small"><RotateCcw size={15}/>복구권 {money(tickets)}장</Link></header>
   <div className="attendance-days">{days.map((day,i)=>{
    const attended=state.attendance.find(a=>a.day===day),past=day<state.day,today=day===state.day;
    const joined=data.session?.profile?.createdAt?new Intl.DateTimeFormat('en-CA',{timeZone:'Asia/Seoul',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date(data.session.profile.createdAt)):'';
    const canRecover=past&&!attended&&(!joined||day>=joined);
    return <div key={day} className={`attendance-day ${attended?'attended':''} ${today?'today':''}`}><span>{['화','수','목','금','토','일','월'][i]}</span><small>{day.slice(5).replace('-','.')}</small><div className="attendance-stamp">{attended?<CheckCircle2 size={29}/>:<span>{String(i+1).padStart(2,'0')}</span>}</div>{attended?<strong>{attended.recovered?'복구 완료':'출석 완료'}</strong>:today?<strong className="mission-auto-attendance">방문 시 자동 출석</strong>:canRecover?<button className="attendance-recover" disabled={busy||!tickets} onClick={()=>void action('recover',{day})}>복구권 사용</button>:<strong className="muted">{past?'참여 전':'출석 예정'}</strong>}</div>;
   })}</div><p className="fine-print">복구권 1장으로 이번 주의 지난 결석일 1일을 복구합니다. 복구 출석은 주간 7일 출석에만 반영되며, 해당 날짜의 일일 미션과 보상은 소급되지 않습니다.</p>
  </section>
  {!!state.unclaimedDaily.length&&<section className="eng-unclaimed"><h3>아직 받지 않은 일일 보상</h3>{state.unclaimedDaily.map(day=><button key={day} className="button secondary small" disabled={busy} onClick={()=>void action('claim_daily',{day})}>{day} · 1,000 P 받기</button>)}</section>}
  <p className="fine-print eng-rules">AI 리포트는 AI 설명이 표시된 조회만 반영합니다. 리포트·시세는 같은 대상당 하루 1회 집계합니다. 경기 미션은 기능 적용 이후 경기 시작 시점의 보유·선발 상태를 기준으로 하며, 미출전 선수는 제외합니다. 출전 7명은 서로 다른 선수 7명입니다. 자동 매각은 주간 매각 미션에서 제외합니다.</p>
 </>;
}
