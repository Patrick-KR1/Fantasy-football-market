"use client";
import { useEffect, useState, type ReactNode } from 'react';
import { cosmeticTheme } from '@/lib/kickx/engagement';
import { usePlatform } from './provider';
import { useEngagement } from './engagement-provider';
import { ClubCrest } from './ui';
const cache = new Map<string,{skin:string|null;at:number}>();
const waiting = new Map<string,Set<(skin:string|null)=>void>>();
let scheduled = false;
function requestName(id:string,callback:(skin:string|null)=>void) {
 const found=cache.get(id);if(found&&Date.now()-found.at<60000){callback(found.skin);return()=>{};}
 const listeners=waiting.get(id)??new Set();listeners.add(callback);waiting.set(id,listeners);
 if(!scheduled){scheduled=true;setTimeout(()=>{
  scheduled=false;const batch=[...waiting.entries()].slice(0,100);for(const [id] of batch)waiting.delete(id);
  void fetch(`/api/kickx/nameplates?users=${batch.map(([id])=>id).join(',')}`,{cache:'no-store'}).then(async r=>{if(!r.ok)throw Error();return await r.json() as Record<string,string>;}).then(result=>{
   for(const [id,listeners] of batch){const skin=result[id]??null;cache.set(id,{skin,at:Date.now()});for(const fn of listeners)fn(skin);}
  }).catch(()=>{});
 },20);}
 return()=>{listeners.delete(callback);};
}
/** Nicknames of 7+ characters are shortened to 6 + "…"; shorter ones always show in full. */
export function nameplateText(name:ReactNode,full=false):{text:ReactNode;title?:string} {
 if(full||typeof name!=='string')return {text:name};
 const chars=[...name];
 return chars.length>=7?{text:chars.slice(0,6).join('')+'…',title:name}:{text:name};
}
export function Nameplate({skin,primaryTeam,children,preview=false,full=false}:{skin?:string|null;primaryTeam?:string|null;children:ReactNode;preview?:boolean;full?:boolean}) {
 const name=nameplateText(children,full);
 if(!skin)return <span className="member-plain-name" title={name.title}>{primaryTeam&&<span className="primary-name-crest" title="메인 응원 구단"><ClubCrest id={primaryTeam} size="small"/></span>}{name.text}</span>;
 const theme=cosmeticTheme(skin);
 return <span className={`kx-nameplate nameplate-${theme} ${preview?'is-preview':''}`}><span className="nameplate-plate" aria-hidden="true"/><span className="nameplate-sigil" title="메인 응원 구단">{primaryTeam&&<ClubCrest id={primaryTeam} size="small"/>}</span><span className="nameplate-text" title={name.title}>{name.text}</span><NameplateArt theme={theme}/></span>;
}
/** Theme ornament outside the plate's right edge, so it never sits on top of the nickname. */
function NameplateArt({theme}:{theme:string}) {
 return <svg className="nameplate-art" viewBox="0 0 36 32" fill="none" aria-hidden="true" focusable="false">
  {NAMEPLATE_ART[theme]??(theme==='arcane'?<>
   <path d="M3 16 15 4l3 8 6-7 1 9 8-4-6 10 6 6-9-2-1 9-5-7-4 8-2-9Z" fill="var(--plate-b)" stroke="var(--plate-a)" strokeWidth="1.2" strokeLinejoin="round"/>
   <path className="nameplate-pulse" d="m19 11 4 5-4 5-4-5Z" fill="#fff" stroke="var(--plate-a)"/>
  </>:theme==='circuit'?<>
   <path d="M1 16h7l3-6h7l3 6h6M11 10V4h8M18 22l3-6m-3 6v6h9" stroke="var(--plate-a)" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round"/>
   <path className="nameplate-pulse" d="m26 5-5 10h5l-4 12 10-14h-6l4-8Z" fill="#effff5" stroke="var(--plate-a)" strokeLinejoin="round"/>
   <circle cx="19" cy="4" r="2" fill="var(--plate-a)"/><circle cx="27" cy="28" r="2" fill="var(--plate-a)"/>
  </>:theme==='inferno'?<>
   <path className="nameplate-flame" d="M2 24q8 1 9-7 4 5 2 10 7-3 6-12 7 6 5 14 6-5 4-13 9 9 4 20H5Z" fill="var(--plate-b)" stroke="var(--plate-a)" strokeWidth="1.2" strokeLinejoin="round"/>
   <path d="M13 28q2-6 6-7 0 4 3 5 2-3 1-6 5 4 2 8Z" fill="#ffd27a"/>
  </>:<>
   <path d="M1 18C11 18 15 6 34 4M1 16c12 1 17 8 33 11M3 17c9-2 14-7 23-7" stroke="var(--plate-a)" strokeWidth="1.6" strokeLinecap="round"/>
   <path d="M1 17c11 0 17 3 24 4" stroke="var(--plate-b)" strokeWidth="2.2" strokeLinecap="round"/>
   <path className="nameplate-pulse" d="m29 12 1.6 3.4L34 17l-3.4 1.6L29 22l-1.6-3.4L24 17l3.4-1.6Z" fill="#fff"/>
  </>)}
 </svg>;
}
export function MemberNameplate({userId,primaryTeam,children,full=false,crest=true}:{userId?:string;primaryTeam?:string|null;children:ReactNode;full?:boolean;crest?:boolean}) {
 const {data}=usePlatform(),{state}=useEngagement();
 const [found,setFound]=useState<{id:string;skin:string|null}|null>(null);
 const own=userId===data.session?.userId;
 useEffect(()=>{
  if(!userId||own||!/^[0-9a-f-]{36}$/i.test(userId))return;
  let unsubscribe=requestName(userId,skin=>setFound({id:userId,skin}));
  const timer=setInterval(()=>{unsubscribe();unsubscribe=requestName(userId,skin=>setFound({id:userId,skin}));},65000);
  return()=>{clearInterval(timer);unsubscribe();};
 },[userId,own]);
 return <Nameplate full={full} primaryTeam={!crest?null:own?data.session?.profile?.primaryTeam:primaryTeam} skin={own?state.loadout.nameplate:found && found.id===userId?found.skin:null}>{children}</Nameplate>;
}

/** Ornaments for the expanded collection (viewBox 0 0 36 32, drawn just past the plate's right edge). */
const NAMEPLATE_ART:Record<string,ReactNode>={
 royal:<><path d="M2 9h20l-4 7 4 7H2Z" fill="var(--plate-b)" stroke="var(--plate-a)" strokeWidth="1.2"/><path d="M14 5l3 5 4-4 1 7h-12l1-7 4 4Z" fill="var(--plate-a)" stroke="#5a3d07" strokeWidth=".8" transform="translate(10 -3)"/><circle className="nameplate-pulse" cx="27" cy="21" r="3" fill="#e0344a" stroke="var(--plate-a)"/></>,
 glacier:<><path d="M2 16 12 5l3 9 6-11 4 13 6-6-3 12 6 4-11 2-4 6-4-7-8 1Z" fill="#dff6ff" stroke="var(--plate-a)" strokeWidth="1.1" strokeLinejoin="round"/><path d="M15 14l3 6 4-5" stroke="#5aa6d6" strokeWidth="1"/><path className="nameplate-pulse" d="m30 3 1 2.4 2.4 1-2.4 1L30 10l-1-2.6-2.4-1L29 5.4Z" fill="#fff"/></>,
 sakura:<>{[[8,10,0],[20,20,40],[30,8,80],[26,27,20]].map(([x,y,r])=><path key={`${x}${y}`} className={x===20?'nameplate-pulse':undefined} d="M0-6c3 0 4 3 2 5l-2 1-2-1c-2-2-1-5 2-5Z" fill="#ffc3dc" stroke="#e05a96" strokeWidth=".7" transform={`translate(${x} ${y}) rotate(${r}) scale(1.25)`}/>)}<circle cx="20" cy="20" r="1.6" fill="#ffe68a"/></>,
 neon:<><path d="M1 9h12M5 15h20M1 21h9M14 21h14" stroke="var(--plate-a)" strokeWidth="2.4" strokeLinecap="round"/><path className="nameplate-pulse" d="M21 6h8v8h-8zM28 18h6v6h-6z" fill="var(--plate-b)"/><path d="M24 26h10" stroke="#fff" strokeWidth="1.5"/></>,
 jungle:<><path d="M1 18C9 12 16 22 26 12" stroke="#2f7a3b" strokeWidth="2.2" strokeLinecap="round"/>{[[8,13,-30],[16,19,40],[24,11,-20],[30,18,30]].map(([x,y,r])=><path key={`${x}${y}`} d="M0 0q5-7 12-3-5 7-12 3Z" fill={x===24?'#f3c84b':'#52b263'} stroke="#1f4d27" strokeWidth=".7" transform={`translate(${x} ${y}) rotate(${r})`}/>)}</>,
 void:<><path d="M2 16q9-1 13-9 1 8 9 5-6 4-2 11-7-5-13 1 1-6-7-8Z" fill="#14081f" stroke="var(--plate-a)" strokeWidth="1.3" strokeLinejoin="round"/><path className="nameplate-pulse" d="M25 4l2 6 6 2-6 2-2 6-2-6-6-2 6-2Z" fill="var(--plate-a)"/><circle cx="31" cy="25" r="2" fill="var(--plate-b)"/></>,
 pixel:<><path d="M4 10h4v-2h4v2h4v-2h4v2h4v4h-2v2h-2v2h-2v2h-4v-2h-2v-2h-2v-2H4Z" fill="#ff4f6d" stroke="#2c1438" strokeWidth=".8" transform="translate(2 1)"/><path className="nameplate-pulse" d="M28 4h3v3h-3zM31 7h3v3h-3zM26 24h3v3h-3z" fill="var(--plate-a)"/></>,
 champion:<><path d="M4 22 1 30l6-3 3 4 2-9M24 22l3 8-6-3-3 4-2-9" fill="#d9263c" stroke="#ffd76b" strokeWidth=".8"/><path d="M8 4h20v5c0 7-4 11-10 12-6-1-10-5-10-12Z" fill="var(--plate-a)" stroke="#6b4a00" strokeWidth="1"/><path d="M8 7H3c0 5 2 7 6 7m19-7h5c0 5-2 7-6 7" stroke="var(--plate-a)" strokeWidth="1.6"/><path className="nameplate-pulse" d="m18 7 1.6 3.2 3.4.5-2.5 2.4.6 3.4-3.1-1.6-3.1 1.6.6-3.4-2.5-2.4 3.4-.5Z" fill="#fff8d8"/></>,
};
