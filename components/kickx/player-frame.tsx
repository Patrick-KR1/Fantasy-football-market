"use client";
import { useId } from 'react';
import type { Player } from '@/lib/kickx/types';
import { PlayerPortrait } from './ui';

/** Ornament themes drawn as vector artwork. The face occupies the circle r=40 at the centre;
    every ornament stays outside r=42 and above y=140 so it never covers the face or the name. */
export const ORNAMENT_THEMES=['laurel','circuit','arcane','seraph','dragon','astral','tempest','bronze','silver','gold','platinum','diamond','master','legend','frost'];
const LAUREL_LEAVES=[0,1,2,3,4,5,6];
/** Original vector ornaments shared by the actual squad and store previews. */
function FrameOrnament({theme}:{theme:string}) {
 const id=useId().replace(/:/g,'');
 if(!ORNAMENT_THEMES.includes(theme))return null;
 return <svg className={`frame-ornament ornament-${theme}`} viewBox="0 0 160 160" fill="none" aria-hidden="true" focusable="false">
  <defs><linearGradient id={`${id}-metal`} x1="20" y1="10" x2="140" y2="145" gradientUnits="userSpaceOnUse"><stop stopColor="var(--frame-light)"/><stop offset=".3" stopColor="var(--frame-main)"/><stop offset=".52" stopColor="var(--frame-light)"/><stop offset=".75" stopColor="var(--frame-deep)"/><stop offset="1" stopColor="var(--frame-main)"/></linearGradient></defs>
  <circle cx="80" cy="80" r="43" stroke={`url(#${id}-metal)`} strokeWidth="4"/>
  <circle cx="80" cy="80" r="48" stroke="var(--frame-main)" strokeWidth="1"/>
  {theme==='laurel'&&<>
   {[1,-1].map(side=><g key={side} transform={side<0?'matrix(-1 0 0 1 160 0)':undefined}>
    <path d="M70 132Q38 124 32 88 30 62 52 39" stroke="var(--frame-deep)" strokeWidth="2.5" strokeLinecap="round"/>
    {LAUREL_LEAVES.map(i=>{const a=(235-i*20)*Math.PI/180,x=80+49*Math.cos(a),y=80-49*Math.sin(a),rot=Math.atan2(Math.cos(a),Math.sin(a))*180/Math.PI+(i%2?-28:28);return <path key={i} d="M0 0q7-6 16-3-7 7-16 3Z" fill={`url(#${id}-metal)`} stroke="var(--frame-deep)" strokeWidth=".8" transform={`translate(${x.toFixed(1)} ${y.toFixed(1)}) rotate(${rot.toFixed(0)})`}/>;})}
   </g>)}
   <path d="m66 130 14 9 14-9-4 12-10-4-10 4Z" fill="var(--frame-main)" stroke="var(--frame-deep)"/>
   <circle cx="80" cy="35" r="3.5" fill="var(--frame-light)"/>
  </>}
  {theme==='circuit'&&<>
   <path className="frame-trace" d="M80 35V21h20l8-8m-28 8H58l-9-9M125 80h12l9-9m-21 9 9 9h10M35 80H23l-9 9m21-9-9-9H16M80 125v11H62l-8 7m26-18v11h17" stroke="var(--frame-main)" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
   {[[108,13],[49,12],[146,71],[144,89],[14,89],[16,71]].map(([x,y])=><circle key={`${x}-${y}`} cx={x} cy={y} r="3" fill="var(--frame-deep)" stroke="var(--frame-light)" strokeWidth="1.5"/>)}
   <circle cx="80" cy="80" r="47" stroke="var(--frame-light)" strokeDasharray="14 6 3 6" strokeWidth="1.5"/>
  </>}
  {theme==='arcane'&&<>
   {[45,135,225,315].map(a=><path key={a} d="M80 18 88 30 80 40 72 30Z" fill={`url(#${id}-metal)`} stroke="var(--frame-light)" strokeWidth="1.2" transform={`rotate(${a} 80 80)`}/>)}
   <path d="M80 15 86 27 80 37 74 27Z" fill="var(--frame-light)" stroke="var(--frame-main)"/>
   <g className="frame-runes" stroke="var(--frame-light)" strokeWidth="1.4" strokeLinecap="round">
    <circle cx="80" cy="80" r="50" stroke="var(--frame-main)" strokeDasharray="1 5"/>
    <path d="M30 70v8l4-4M127 68l4 6 4-6M33 96l5-4v8M125 96h8l-4 6"/>
   </g>
  </>}
  {theme==='seraph'&&<>
   <path d="M38 61 7 28 14 66 25 82 13 78 22 99 41 108 34 91 39 81Z" fill={`url(#${id}-metal)`} stroke="var(--frame-light)"/>
   <path d="m122 61 31-33-7 38-11 16 12-4-9 21-19 9 7-17-5-10Z" fill={`url(#${id}-metal)`} stroke="var(--frame-light)"/>
   <path d="m15 43 21 29M19 61l17 19m-10 9 11 5m108-51-21 29m17-11-17 19m10 9-11 5" stroke="var(--frame-deep)" strokeWidth="2"/>
   <path d="m61 32-4-17 14 8L80 6l9 17 14-8-4 17Z" fill={`url(#${id}-metal)`} stroke="var(--frame-light)" strokeWidth="1.5"/>
   <path d="m80 124 5 7-5 9-5-9Z" fill="var(--frame-main)" stroke="var(--frame-light)"/>
  </>}
  {theme==='dragon'&&<>
   <path d="M36 54 8 27l6 31L3 71l21 6-4 26 23-9-12-17Zm88 0 28-27-6 31 11 13-21 6 4 26-23-9 12-17Z" fill="var(--frame-deep)" stroke={`url(#${id}-metal)`} strokeWidth="3"/>
   <path d="m18 45 19 21-13 3 9 19M142 45l-19 21 13 3-9 19" stroke="var(--frame-main)" strokeWidth="2"/>
   <path d="m52 42-6-20 20 12L80 16l14 18 20-12-6 20M55 120l11 9 14-5 14 5 11-9" stroke={`url(#${id}-metal)`} strokeWidth="4"/>
   <path className="frame-fire" d="M71 140q-5-8 3-13 0 6 6 8 7-5 4-12 15 12-13 17Z" fill="var(--frame-main)" stroke="var(--frame-light)"/>
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
  {['bronze','silver','gold','master','legend'].includes(theme)&&[1,-1].map(side=><g key={`wing${side}`} transform={side<0?'matrix(-1 0 0 1 160 0)':undefined}>
   {/* Tiered wing: bronze has two feathers, each tier adds one. */}
   {Array.from({length:{bronze:2,silver:3,gold:3,master:4,legend:5}[theme]??3},(_,i)=><path key={i} d={`M39 ${70+i*6}Q${20-i*3} ${58+i*9} ${8-i*1} ${46+i*13}Q${22-i*2} ${74+i*6} 40 ${84+i*4}Z`} fill={`url(#${id}-metal)`} stroke="var(--frame-deep)" strokeWidth=".9"/>)}
  </g>)}
  {theme==='bronze'&&<path d="m64 124 16 15 16-15-4-6H68Z" fill={`url(#${id}-metal)`} stroke="var(--frame-deep)" strokeWidth="1.2"/>}
  {theme==='silver'&&<><path d="m80 22 7 10-7 9-7-9Z" fill="var(--frame-light)" stroke="var(--frame-deep)"/><path d="m70 126 10 12 10-12" stroke={`url(#${id}-metal)`} strokeWidth="3" strokeLinejoin="round"/></>}
  {theme==='gold'&&<>
   <path d="M62 20h36v10c0 9-8 14-18 18-10-4-18-9-18-18Z" fill={`url(#${id}-metal)`} stroke="var(--frame-deep)" strokeWidth="1.2"/>
   <path d="M71 26h18M80 22v18" stroke="var(--frame-deep)" strokeWidth="1.5"/>
   <path d="m80 122 7 8-7 9-7-9Z" fill="#e0344a" stroke="var(--frame-light)"/>
  </>}
  {theme==='platinum'&&<>
   {[[-24,15],[0,22],[24,15]].map(([dx,h])=><path key={dx} d={`m${80+dx} ${37-h}l7 ${h-4}-7 6-7-6Z`} fill={`url(#${id}-metal)`} stroke="var(--frame-light)" strokeWidth="1"/>)}
   {[1,-1].map(side=><path key={side} d={side>0?'m124 70 18-8-6 18 6 18-18-8Z':'m36 70-18-8 6 18-6 18 18-8Z'} fill="var(--frame-main)" stroke="var(--frame-light)"/>)}
   <path d="m70 126 10 10 10-10" stroke="var(--frame-light)" strokeWidth="2"/>
  </>}
  {theme==='diamond'&&<>
   <ellipse className="frame-halo" cx="80" cy="22" rx="24" ry="6" stroke="var(--frame-light)" strokeWidth="2.5"/>
   <path d="M66 32h28l-14 20Zm0 0 6-8h16l6 8" fill={`url(#${id}-metal)`} stroke="var(--frame-light)" strokeWidth="1.2" strokeLinejoin="round"/>
   {[1,-1].map(side=><path key={side} d={side>0?'m122 64 22-10-8 22 10 14-22-4Z':'m38 64-22-10 8 22-10 14 22-4Z'} fill={`url(#${id}-metal)`} stroke="var(--frame-light)"/>)}
   <path d="m80 122 6 8-6 8-6-8Z" fill="var(--frame-light)"/>
  </>}
  {theme==='master'&&<>
   <path d="m54 36-6-22 14 10 8-16 10 14 10-14 8 16 14-10-6 22Z" fill={`url(#${id}-metal)`} stroke="var(--frame-light)" strokeWidth="1.3" strokeLinejoin="round"/>
   {[62,80,98].map(x=><circle key={x} cx={x} cy={x===80?22:27} r="3" fill="#ff5fd1" stroke="var(--frame-light)"/>)}
   <path d="m66 124 14 14 14-14-6-4H72Z" fill={`url(#${id}-metal)`} stroke="var(--frame-light)"/>
  </>}
  {theme==='legend'&&<>
   <g className="frame-rays">{Array.from({length:16},(_,i)=>i>=5&&i<=11?null:<path key={i} d="M80 26V8" stroke="var(--frame-light)" strokeWidth={i%2?1.2:2.4} strokeLinecap="round" opacity={i%2?.6:1} transform={`rotate(${i*22.5} 80 80)`}/>)}</g>
   <circle cx="80" cy="80" r="50" stroke="var(--frame-main)" strokeWidth="3"/>
   <circle cx="80" cy="80" r="50" stroke="var(--frame-light)" strokeWidth="1.2" strokeDasharray="40 8 4 8"/>
   <path d="m58 34-4-18 12 8 14-14 14 14 12-8-4 18Z" fill={`url(#${id}-metal)`} stroke="var(--frame-deep)" strokeWidth="1.2" strokeLinejoin="round"/>
   <circle cx="80" cy="22" r="4" fill="#fff6c9"/>
  </>}
  {theme==='frost'&&<>
   {[0,45,90,135,180,225,270,315].map(a=><path key={a} d={a%90?'M80 30 84 17 80 8 76 17Z':'M80 32 86 15 80 2 74 15Z'} fill={`url(#${id}-metal)`} stroke="var(--frame-light)" strokeWidth=".8" transform={`rotate(${a} 80 80)`} opacity={a===180?0:1}/>)}
   {[[26,40],[134,40],[30,120],[130,120]].map(([x,y])=><path key={`${x}${y}`} className="frame-snow" d={`M${x} ${y-6}v12M${x-6} ${y}h12M${x-4} ${y-4}l8 8m0-8-8 8`} stroke="var(--frame-light)" strokeWidth="1.4" strokeLinecap="round"/>)}
  </>}
 </svg>;
}
export function FramedPlayer({player,theme='default',preview=false}:{player?:Player;theme?:string;preview?:boolean}) {
 const ornate=ORNAMENT_THEMES.includes(theme);
 return <span className={`squad-player-icon squad-face player-frame frame-${theme} ${ornate?'frame-ornate':''} ${preview?'is-preview':''}`}>
  {player?<PlayerPortrait player={player} size={preview?'lg':'md'}/>:<span className="cosmetic-player-placeholder">✦</span>}
  <FrameOrnament theme={theme}/>
 </span>;
}
