"use client";
import Link from 'next/link';
import { useRef, useState } from 'react';
import { useSearchParams } from 'next/navigation';
import { Check, ShoppingBag, Ticket, Wallet, ArrowUpRight } from 'lucide-react';
import { money } from '@/lib/kickx/data';
import { type ShopItem, type ShopCategory } from '@/lib/kickx/engagement';
import { usePlatform } from './provider';
import { useEngagement } from './engagement-provider';
import { EngagementNotice } from './missions';
import { Nameplate } from './nameplate';
import { FramedPlayer } from './player-frame';
import { PitchScenery } from './pitch-scenery';
import { Modal, PageHeading } from './ui';
import { Pagination } from './pagination';
const PAGE_SIZE=9;
const CATEGORIES:{id:ShopCategory|'all';label:string}[]=[{id:'all',label:'전체'},{id:'nameplate',label:'네임태그'},{id:'frame',label:'선수 테두리'},{id:'pitch',label:'경기장'},{id:'ticket',label:'출석 복구권'}];
export function ShopPreview({item}:{item:ShopItem}) {
 const {data}=usePlatform();
 const player=data.member?.ownedPlayers?.[0]??data.players[0];
 if(item.category==='nameplate')return <div className={`shop-preview nameplate-preview preview-${item.theme}`}><Nameplate skin={item.id} primaryTeam={data.session?.profile?.primaryTeam??data.teams[0]?.id} preview>{data.session?.profile?.nickname??'KICK-X PLAYER'}</Nameplate></div>;
 if(item.category==='frame')return <div className={`shop-preview frame-preview preview-${item.theme}`}><FramedPlayer player={player} theme={item.theme} preview/></div>;
 if(item.category==='pitch')return <div className={`shop-preview pitch-preview pitch-theme-${item.theme}`}><PitchScenery theme={item.theme}/><svg viewBox="0 0 280 150" aria-hidden="true"><rect x="28" y="13" width="224" height="124"/><path d="M140 13v124M28 45h37v60H28M252 45h-37v60h37"/><circle cx="140" cy="75" r="25"/><circle className="fill" cx="140" cy="75" r="2"/></svg><span className="preview-pitch-label">{({myth:'OLYMPUS',engineering:'MECHA GRID',christmas:'WINTER VILLAGE',volcano:'MAGMA ARENA',cosmos:'STARLIGHT',sky:'SKY ISLAND',arcade:'NEON ARCADE',desert:'OASIS',deepsea:'DEEP BLUE',blossom:'BLOSSOM GARDEN',haunted:'MOONLIGHT HOLLOW',candy:'CANDY LAND',ruins:'JUNGLE TEMPLE'} as Record<string,string>)[item.theme]}</span></div>;
 return <div className="shop-preview ticket-preview"><span className="ticket-art"><Ticket size={42}/><strong>ATTENDANCE<br/>RECOVERY</strong><small>×1 DAY</small></span></div>;
}
export function ShopScreen() {
 const {data,notify}=usePlatform(),{state,ready,busy,act}=useEngagement();
 const query=useSearchParams();
 const [category,setCategory]=useState<string>(CATEGORIES.some(c=>c.id===query.get('category'))?query.get('category')!:'all');
 const [selected,setSelected]=useState<ShopItem|null>(null);
 const [page,setPage]=useState(1);
 const listed=state.catalog.filter(i=>category==='all'||i.category===category);
 const pages=Math.max(1,Math.ceil(listed.length/PAGE_SIZE)),shown=Math.min(page,pages);
 function turn(next:number){setPage(next);document.querySelector('.shop-toolbar')?.scrollIntoView({behavior:'smooth',block:'start'});}
 const request=useRef<{item:string;id:string}|null>(null);
 function open(item:ShopItem){if(request.current?.item!==item.id)request.current={item:item.id,id:crypto.randomUUID()};setSelected(item);}
 async function buy(){if(!selected||!request.current)return;if(await act('purchase',{itemId:selected.id,requestId:request.current.id})){notify(`${selected.name} 구매가 완료됐습니다.`);request.current=null;setSelected(null);}}
 async function equip(item:ShopItem){const equipped=state.loadout[item.category as 'nameplate'|'frame'|'pitch']===item.id;if(await act('equip',{category:item.category,itemId:equipped?null:item.id}))notify(equipped?'기본 디자인을 적용했습니다.':`${item.name} 디자인을 적용했습니다.`);}
 return <>
  <PageHeading eyebrow="MAKE THE GAME YOURS" title="포인트 상점" description="플레이로 모은 포인트로, 나만의 축구 세계를 꾸미세요." action={<Link href="/missions" className="button secondary">미션으로 포인트 모으기 <ArrowUpRight size={16}/></Link>}/>
  <EngagementNotice/>
  <div className="eng-hero shop-hero"><div><span className="eng-kicker">THE KICK-X COLLECTION</span><h2>나를 보여주는<br/><em>또 하나의 플레이.</em></h2><p>네임태그부터 나만의 홈 경기장까지.<br/>구매한 꾸미기는 언제든 다시 장착할 수 있습니다.</p></div><div className="shop-hero-display"><Nameplate skin="nameplate-circuit" primaryTeam={data.session?.profile?.primaryTeam??data.teams[0]?.id} preview>{data.session?.profile?.nickname??'KICK-X PLAYER'}</Nameplate><span className="eng-kicker">YOUR NAME. YOUR SIGNATURE.</span></div></div>
  <div className="shop-toolbar"><div className="shop-tabs" role="group" aria-label="상품 분류">{CATEGORIES.map(c=><button key={c.id} className={category===c.id?'active':''} aria-pressed={category===c.id} onClick={()=>{setCategory(c.id);setPage(1);}}>{c.label}</button>)}</div><div className="shop-balance"><Wallet size={17}/><span>보유</span><strong className="num">{money(data.member?.points)} P</strong></div></div>
  <div className="shop-grid">{listed.slice((shown-1)*PAGE_SIZE,shown*PAGE_SIZE).map(item=>{
   const quantity=state.inventory[item.id]??0,owned=quantity>0,equipped=item.category!=='ticket'&&state.loadout[item.category]===item.id;
   return <article className={`shop-card ${equipped?'equipped':''}`} key={item.id}><ShopPreview item={item}/><div className="shop-card-body"><span className="shop-category">{CATEGORIES.find(c=>c.id===item.category)?.label}{equipped&&<small><Check size={12}/>장착 중</small>}</span><h3>{item.name}</h3><p>{item.description}</p><footer><strong className="num">{money(item.price)} <small>P</small></strong>{owned&&item.category!=='ticket'?<button className="button secondary small" disabled={!ready||busy} onClick={()=>void equip(item)}>{equipped?'장착 해제':'장착하기'}</button>:<button className="button small" disabled={!ready||busy} onClick={()=>open(item)}><ShoppingBag size={14}/>구매</button>}</footer>{item.category==='ticket'&&<small className="inventory-quantity">보유 {quantity}장 · <Link href="/missions">출석 복구하기</Link></small>}</div></article>;
  })}</div>
  {listed.length>PAGE_SIZE&&<div className="shop-pagination"><Pagination page={shown} total={listed.length} size={PAGE_SIZE} onPage={turn} label="상품 페이지" centered/></div>}
  <div className="shop-squad-link"><Link href="/squad" className="button secondary small">스쿼드로 이동</Link></div>
  {ready&&state.catalog.some(i=>i.category===category||category==='all')&&<p className="fine-print">치장 상품은 포인트로 구매하며 선수 능력치나 뽑기 확률에 영향을 주지 않습니다. 출석 복구권은 1회 사용하면 소모됩니다. 장착한 네임태그는 프로필·커뮤니티·랭킹에 표시됩니다.</p>}
  {selected&&<Modal title="상품 구매" eyebrow="POINT SHOP" onClose={()=>{if(!busy)setSelected(null);}}><ShopPreview item={selected}/><div className="shop-confirm"><h3>{selected.name}</h3><p>{selected.description}</p><dl><div><dt>구매 가격</dt><dd className="num">{money(selected.price)} P</dd></div><div><dt>구매 후 포인트</dt><dd className="num">{money((data.member?.points??0)-selected.price)} P</dd></div></dl><button className="button" disabled={busy||(data.member?.points??0)<selected.price} onClick={()=>void buy()}>{busy?'구매 중…':(data.member?.points??0)<selected.price?'포인트가 부족합니다':'포인트로 구매하기'}</button></div></Modal>}
 </>;
}
