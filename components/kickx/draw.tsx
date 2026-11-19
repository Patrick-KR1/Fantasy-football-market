"use client";
import Link from 'next/link';
import { useRef, useState } from 'react';
import { ArrowRight, Check, Clock3, Shuffle, Sparkles, Wallet } from 'lucide-react';
import { apiRequest } from '@/lib/kickx/client';
import { money } from '@/lib/kickx/data';
import { formationRule, SQUAD_FORMATION } from '@/lib/kickx/squad';
import type { DrawReceipt } from '@/lib/kickx/engagement';
import type { Player } from '@/lib/kickx/types';
import { usePlatform, useResource } from './provider';
import { useEngagement } from './engagement-provider';
import { EngagementNotice } from './missions';
import { Modal, PageHeading, PlayerPortrait, PositionBadge } from './ui';
const emptyPlayer=()=>({player:null as Player|null});
function Placement({receipt,onDone}:{receipt:DrawReceipt;onDone:(r:DrawReceipt)=>void}) {
 const {data,getPlayer,notify,reload:reloadPlatform}=usePlatform(),{reload}=useEngagement();
 const {data:detail,status}=useResource(`/api/kickx/players/${encodeURIComponent(receipt.player_id)}`,emptyPlayer);
 const player=detail.player??getPlayer(receipt.player_id);
 const [choice,setChoice]=useState<{draw:string;bench:string|null}|null>(null),[busy,setBusy]=useState(false);
 const lock=useRef(false),member=data.member,active=member?.holdings.filter(h=>!h.bench)??[];
 const position=player?.position;
 const formation=formationRule(member?.squad?.formationId??'4-3-3')??SQUAD_FORMATION;
 const cap=formation.positions.filter(p=>p===position).length;
 const used=active.filter(h=>getPlayer(h.playerId)?.position===position).length;
 const positionFull=!!position&&used>=cap,full=active.length>=11||positionFull;
 const locked=!!player?.tradeWindow?.locked;
 const effective=choice?.draw===receipt.id?choice.bench:full||locked||!player?receipt.player_id:null;
 async function place(){
  if(lock.current)return;lock.current=true;setBusy(true);
  try{const r=await apiRequest<DrawReceipt>('/api/kickx/engagement','POST',{action:'place_draw',input:{drawId:receipt.id,benchPlayer:effective}});onDone(r);notify(r.status==='duplicate'?'이미 보유한 선수이므로 포인트로 전환했습니다.':'선수 배치를 완료했습니다.');reloadPlatform();reload();}
  catch(e){notify(e instanceof Error?e.message:'선수 배치를 저장하지 못했습니다.','error');reload();reloadPlatform();}
  finally{lock.current=false;setBusy(false);}
 }
 return <section className="draw-result"><div className="draw-result-player"><span className="eng-kicker">YOUR NEW SIGNING</span><div className="draw-player-art">{player?<PlayerPortrait player={player} size="lg"/>:<span className="cosmetic-player-placeholder">✦</span>}<Sparkles size={30}/></div><h2>{receipt.player_name}</h2><div>{position&&<PositionBadge position={position}/>}<span className="num">뽑기 당시 {money(receipt.price_at_draw)} P</span></div><p>뽑기 확률 <strong className="num">1 / {money(receipt.pool_size)}</strong> · 모든 대상 선수 동일</p><Link href={`/players/${encodeURIComponent(receipt.player_id)}`}>선수 자세히 보기 <ArrowRight size={14}/></Link></div>
  <div className="draw-placement"><span className="eng-kicker">COMPLETE YOUR ROSTER</span><h3>{full?'벤치로 보낼 선수를 선택하세요':'선수의 자리를 정하세요'}</h3><p>{locked?'경기 거래 제한 중인 선수는 우선 벤치에 보관합니다. 제한이 풀리면 스쿼드에서 복귀할 수 있습니다.':positionFull?'같은 포지션의 기존 선수 또는 뽑은 선수를 벤치로 보낼 수 있습니다.':'뽑은 선수를 바로 영입하거나, 기존 선수와 자리를 바꿀 수 있습니다.'}</p>
   <div className="draw-choices" role="radiogroup" aria-label="벤치 이동 선수 선택">
    {!full&&!locked&&player&&<button role="radio" aria-checked={effective===null} className={effective===null?'selected':''} disabled={busy} onClick={()=>setChoice({draw:receipt.id,bench:null})}><span className="draw-choice-mark">{effective===null&&<Check size={16}/>}</span><span><strong>빈 선발 자리에 영입</strong><small>{position} 포지션에 자동 배치</small></span></button>}
    <button role="radio" aria-checked={effective===receipt.player_id} className={effective===receipt.player_id?'selected':''} disabled={busy} onClick={()=>setChoice({draw:receipt.id,bench:receipt.player_id})}><span className="draw-choice-mark">{effective===receipt.player_id&&<Check size={16}/>}</span><span><strong>{receipt.player_name}</strong><small>이번에 뽑은 선수를 벤치로</small></span></button>
    {active.map(h=>{const p=getPlayer(h.playerId);const disabled=busy||locked||!position||positionFull&&p?.position!==position||!!p?.tradeWindow?.locked;return <button key={h.playerId} role="radio" aria-checked={effective===h.playerId} className={effective===h.playerId?'selected':''} disabled={disabled} onClick={()=>setChoice({draw:receipt.id,bench:h.playerId})}><span className="draw-choice-mark">{effective===h.playerId&&<Check size={16}/>}</span>{p&&<PlayerPortrait player={p} size="sm"/>}<span><strong>{p?.name??h.playerName}</strong><small>{p?.position??'포지션 확인 중'} · {p?.tradeWindow?.locked?'거래 제한 중':positionFull&&p?.position!==position?'다른 포지션':'기존 선수를 벤치로'}</small></span></button>;})}
   </div>
   <button className="button draw-place-button" disabled={busy||status==='loading'} onClick={()=>void place()}>{busy?'배치 저장 중…':'선수 배치 완료'}<ArrowRight size={17}/></button>
   <p className="fine-print">벤치 보관 기간은 7일입니다. 기한이 지나면 기존 벤치 정책에 따라 자동 매각됩니다. 벤치에서도 선수 가치는 현재 시세를 따릅니다.</p>
  </div>
 </section>;
}
export function DrawScreen() {
 const {data,notify,reload:reloadPlatform}=usePlatform(),{state,ready,reload}=useEngagement();
 const [confirm,setConfirm]=useState(false),[busy,setBusy]=useState(false),[receipt,setReceipt]=useState<DrawReceipt|null>(null);
 const request=useRef<string|null>(null),lock=useRef(false);
 const pending=state.draw.pending[0]??(receipt?.status==='pending'?receipt:null);
 const canDraw=ready&&state.draw.remaining>0&&!pending&&(data.member?.points??0)>=100000;
 async function draw(){
  if(lock.current)return;lock.current=true;setBusy(true);request.current??=crypto.randomUUID();
  try{const result=await apiRequest<DrawReceipt>('/api/kickx/engagement','POST',{action:'draw',input:{requestId:request.current}});setReceipt(result);setConfirm(false);request.current=null;reload();reloadPlatform();}
  catch(e){notify(e instanceof Error?e.message:'뽑기를 완료하지 못했습니다.','error');reload();reloadPlatform();}
  finally{lock.current=false;setBusy(false);}
 }
 return <>
  <PageHeading eyebrow="ONE TICKET. A NEW POSSIBILITY." title="선수 뽑기" description="하루 한 번, 모든 선수에게 같은 확률. 다음 영입은 누구일까요?" action={<Link className="button secondary" href="/missions">미션 보상 모으기</Link>}/>
  <EngagementNotice/>
  {!pending&&<div className="draw-stage"><div className="draw-stage-copy"><span className="eng-kicker">DAILY PLAYER DRAW</span><h2>오늘의<br/><em>새로운 영입.</em></h2><p>5대 리그 선수 중 무작위 1명을 영입합니다.<br/>선수 가치와 보유 여부에 관계없이 확률은 같습니다.</p><div className="draw-price"><strong className="num">100,000 <small>P</small></strong><span>하루 1회 · 한국 시간 00:00 초기화</span></div><button className="button draw-open" disabled={!canDraw||busy} onClick={()=>setConfirm(true)}><Shuffle size={21}/>{busy?'추첨 중…':!ready?(data.session?'정보 확인 중…':'로그인 후 이용'):state.draw.remaining===0?'오늘의 뽑기 완료':(data.member?.points??0)<100000?'포인트가 부족합니다':'선수 뽑기'}</button>{!!state.draw.poolSize&&<span className="draw-pool-size">현재 대상 {money(state.draw.poolSize)}명 · 선수당 {(100/state.draw.poolSize).toFixed(4)}%</span>}<span className="draw-wallet"><Wallet size={15}/>보유 <strong className="num">{money(data.member?.points)} P</strong></span></div><div className="draw-pack" aria-hidden="true"><div className="draw-pack-shadow"/><div className="draw-pack-card"><span>KICK-X</span><Sparkles size={54}/><strong>WHO’S<br/>NEXT?</strong><small>PLAYER DRAW / 01</small></div><span className="draw-pack-orbit orbit-one"/><span className="draw-pack-orbit orbit-two"/><span className="draw-pack-dot"/></div></div>}
  {pending&&<Placement key={pending.id} receipt={pending} onDone={r=>setReceipt(r)}/>}
  {!pending&&receipt&&<div className="draw-settled" role="status"><Check size={22}/><div><strong>{receipt.player_name}</strong><p>{receipt.status==='duplicate'?`이미 보유한 선수입니다. ${money(receipt.compensation)} P로 전환했습니다.`:'선수 배치를 완료했습니다. 스쿼드에서 확인하세요.'}</p></div><Link className="button secondary small" href="/squad">스쿼드 확인</Link></div>}
  <div className="draw-policies"><article><Shuffle size={22}/><h3>모두에게 같은 확률</h3><p>현재 가격 산정이 완료된 5대 리그 거래 대상 선수 전체가 같은 확률로 등장합니다. 이미 보유한 선수도 포함합니다.</p></article><article><Clock3 size={22}/><h3>하루 한 번의 영입</h3><p>매일 한국 시간 00:00에 구매 제한이 초기화됩니다. 미배치 결과가 남아 있으면 배치를 먼저 완료해 주세요.</p></article><article><Wallet size={22}/><h3>보유 선수 중복 시 포인트 전환</h3><p>뽑기 당시 시세에서 매각 수수료 {((data.policy?.sellFeeBps??200)/100).toFixed(0)}%를 제외한 포인트를 받습니다. 실제 선수 매각 미션에는 포함되지 않습니다.</p></article></div>
  {!!state.draw.history.length&&<section className="draw-history"><header><h2>최근 뽑기 기록</h2><span className="muted">최근 20회</span></header><div className="table-wrap"><table><thead><tr><th>날짜</th><th>선수</th><th>당시 가치</th><th>결과</th></tr></thead><tbody>{state.draw.history.map(r=><tr key={r.id}><td className="num">{r.day}</td><td><Link href={`/players/${encodeURIComponent(r.player_id)}`}>{r.player_name}</Link></td><td className="num">{money(r.price_at_draw)} P</td><td>{r.status==='duplicate'?`${money(r.compensation)} P 전환`:r.status==='pending'?'배치 대기':r.bench_player?'벤치 선택 완료':'선발 영입'}</td></tr>)}</tbody></table></div></section>}
  {confirm&&<Modal title="선수를 뽑을까요?" eyebrow="DAILY PLAYER DRAW" onClose={()=>{if(!busy)setConfirm(false);}}><div className="draw-confirm"><Sparkles size={38}/><p>100,000 P를 사용해 선수 1명을 무작위로 뽑습니다.</p><p className="fine-print">결과는 서버에 저장됩니다. 창을 닫거나 새로고침해도 선수가 다시 추첨되지 않습니다.</p><button className="button" disabled={busy||!canDraw} onClick={()=>void draw()}>{busy?'선수를 추첨하고 있습니다…':'100,000 P로 뽑기'}</button></div></Modal>}
 </>;
}
