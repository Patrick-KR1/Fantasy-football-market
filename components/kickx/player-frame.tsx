"use client";
import { useId } from 'react';
import type { Player } from '@/lib/kickx/types';
import { PlayerPortrait } from './ui';

/** Original vector ornaments shared by the actual squad and store previews. */
function FrameOrnament({theme}:{theme:string}) {
 const id=useId().replace(/:/g,'');
 if(!['seraph','dragon','astral','tempest'].includes(theme))return null;
 return <svg className={`frame-ornament ornament-${theme}`} viewBox="0 0 160 160" fill="none" aria-hidden="true" focusable="false">
  <defs><linearGradient id={`${id}-metal`} x1="20" y1="10" x2="140" y2="145" gradientUnits="userSpaceOnUse"><stop stopColor="var(--frame-light)"/><stop offset=".3" stopColor="var(--frame-main)"/><stop offset=".52" stopColor="var(--frame-light)"/><stop offset=".75" stopColor="var(--frame-deep)"/><stop offset="1" stopColor="var(--frame-main)"/></linearGradient></defs>
  <circle cx="80" cy="80" r="43" stroke={`url(#${id}-metal)`} strokeWidth="4"/>
  <circle cx="80" cy="80" r="48" stroke="var(--frame-main)" strokeWidth="1"/>
  {theme==='seraph'&&<>
   <path d="M38 61 7 28 14 66 25 82 13 78 22 99 41 108 34 91 39 81Z" fill={`url(#${id}-metal)`} stroke="var(--frame-light)"/>
   <path d="m122 61 31-33-7 38-11 16 12-4-9 21-19 9 7-17-5-10Z" fill={`url(#${id}-metal)`} stroke="var(--frame-light)"/>
   <path d="m15 43 21 29M19 61l17 19m-10 9 11 5m108-51-21 29m17-11-17 19m10 9-11 5" stroke="var(--frame-deep)" strokeWidth="2"/>
   <path d="m61 32-4-17 14 8L80 6l9 17 14-8-4 17Z" fill={`url(#${id}-metal)`} stroke="var(--frame-light)" strokeWidth="1.5"/>
   <path d="m80 123 6 9-6 15-6-15Z" fill="var(--frame-main)" stroke="var(--frame-light)"/>
  </>}
  {theme==='dragon'&&<>
   <path d="M36 54 8 27l6 31L3 71l21 6-4 26 23-9-12-17Zm88 0 28-27-6 31 11 13-21 6 4 26-23-9 12-17Z" fill="var(--frame-deep)" stroke={`url(#${id}-metal)`} strokeWidth="3"/>
   <path d="m18 45 19 21-13 3 9 19M142 45l-19 21 13 3-9 19" stroke="var(--frame-main)" strokeWidth="2"/>
   <path d="m52 42-6-20 20 12L80 16l14 18 20-12-6 20M55 118l11 11 14-6 14 6 11-11" stroke={`url(#${id}-metal)`} strokeWidth="4"/>
   <path className="frame-fire" d="M69 133q-6-13 5-22-1 12 6 16 13-10 8-23 22 25-8 46Z" fill="var(--frame-main)" stroke="var(--frame-light)"/>
  </>}
  {theme==='astral'&&<>
   <g className="frame-orbit"><ellipse cx="80" cy="80" rx="69" ry="24" transform="rotate(-32 80 80)" stroke="var(--frame-main)" strokeWidth="2"/><ellipse cx="80" cy="80" rx="67" ry="29" transform="rotate(40 80 80)" stroke="var(--frame-light)" strokeOpacity=".7"/><circle cx="22" cy="114" r="5" fill="var(--frame-main)"/><circle cx="132" cy="43" r="4" fill="var(--frame-light)"/></g>
   <path d="m80 8 5 13 13 5-13 5-5 13-5-13-13-5 13-5Zm48 101 4 10 10 4-10 4-4 10-4-10-10-4 10-4Z" fill={`url(#${id}-metal)`}/>
   <circle cx="80" cy="80" r="53" stroke="var(--frame-main)" strokeDasharray="2 9"/>
  </>}
  {theme==='tempest'&&<>
   <path className="frame-bolt" d="m36 33-20 42 17-2-10 38 28-50-18 3Zm89-3 19 43-17-2 10 39-27-51 17 3Z" fill="var(--frame-light)" stroke="var(--frame-main)" strokeWidth="2"/>
   <path d="m52 37 6-17 12 9L80 9l10 20 12-9 6 17M52 121l10 10h36l10-10" fill={`url(#${id}-metal)`} stroke="var(--frame-light)" strokeWidth="2"/>
   <path d="m42 111-9 10 13 6 12 11h44l12-11 13-6-9-10" stroke="var(--frame-main)" strokeWidth="2"/>
   <circle cx="80" cy="80" r="51" stroke="var(--frame-light)" strokeDasharray="9 5 2 8"/>
  </>}
 </svg>;
}
export function FramedPlayer({player,theme='default',preview=false}:{player?:Player;theme?:string;preview?:boolean}) {
 const ornate=['seraph','dragon','astral','tempest'].includes(theme);
 return <span className={`squad-player-icon squad-face player-frame frame-${theme} ${ornate?'frame-ornate':''} ${preview?'is-preview':''}`}>
  {player?<PlayerPortrait player={player} size={preview?'lg':'md'}/>:<span className="cosmetic-player-placeholder">✦</span>}
  <FrameOrnament theme={theme}/>
 </span>;
}
