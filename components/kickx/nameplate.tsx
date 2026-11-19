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
export function Nameplate({skin,primaryTeam,children,preview=false}:{skin?:string|null;primaryTeam?:string|null;children:ReactNode;preview?:boolean}) {
 if(!skin)return <span className="member-plain-name">{primaryTeam&&<span className="primary-name-crest" title="메인 응원 구단"><ClubCrest id={primaryTeam} size="small"/></span>}{children}</span>;
 return <span className={`kx-nameplate nameplate-${cosmeticTheme(skin)} ${preview?'is-preview':''}`}><span className="nameplate-sigil" title="메인 응원 구단">{primaryTeam&&<ClubCrest id={primaryTeam} size="small"/>}</span><span className="nameplate-text">{children}</span><span className="nameplate-tail" aria-hidden="true"/></span>;
}
export function MemberNameplate({userId,primaryTeam,children}:{userId?:string;primaryTeam?:string|null;children:ReactNode}) {
 const {data}=usePlatform(),{state}=useEngagement();
 const [found,setFound]=useState<{id:string;skin:string|null}|null>(null);
 const own=userId===data.session?.userId;
 useEffect(()=>{
  if(!userId||own||!/^[0-9a-f-]{36}$/i.test(userId))return;
  let unsubscribe=requestName(userId,skin=>setFound({id:userId,skin}));
  const timer=setInterval(()=>{unsubscribe();unsubscribe=requestName(userId,skin=>setFound({id:userId,skin}));},65000);
  return()=>{clearInterval(timer);unsubscribe();};
 },[userId,own]);
 return <Nameplate primaryTeam={own?data.session?.profile?.primaryTeam:primaryTeam} skin={own?state.loadout.nameplate:found && found.id===userId?found.skin:null}>{children}</Nameplate>;
}
