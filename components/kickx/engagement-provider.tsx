"use client";
import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState, type ReactNode } from 'react';
import { usePlatform, useResource } from './provider';
import { apiRequest } from '@/lib/kickx/client';
import { emptyEngagement, emptyShop, type Engagement, type Loadout } from '@/lib/kickx/engagement';
type ContextValue = { state: Engagement; ready: boolean; error: boolean; busy: boolean; reload: () => void; act: (action: string, input?: Record<string, unknown>) => Promise<boolean>; track: (kind: string, target: string) => void };
const Context = createContext<ContextValue | null>(null);
export function EngagementProvider({ children }: { children: ReactNode }) {
 const { data, reload: reloadPlatform, notify } = usePlatform();
 const userId = data.session?.profile ? data.session.userId : null;
 // Identity in the URL prevents another account's inventory appearing for one render.
 const resource = useResource(userId ? `/api/kickx/engagement?member=${encodeURIComponent(userId)}` : null, emptyEngagement, 60000);
 const preview = useResource(userId ? null : '/api/kickx/shop',emptyShop);
 const state=useMemo(()=>userId?resource.data:{...resource.data,catalog:preview.data.catalog,draw:{...resource.data.draw,poolSize:preview.data.poolSize}},[userId,resource.data,preview.data]);
 const {setData:setEngagement,reload:reloadEngagement}=resource;
 const [busy, setBusy] = useState(false), lock = useRef(false);
 const currentUser = useRef(userId); currentUser.current = userId;
 const tracked = useRef(new Set<string>());
 const act = useCallback(async (action: string, input: Record<string, unknown> = {}) => {
  if (!userId || lock.current) return false;
  const owner = userId; lock.current = true; setBusy(true);
  try {
   const next = await apiRequest<Engagement>('/api/kickx/engagement','POST',{ action, input });
   if (currentUser.current === owner) { setEngagement(next); if(action==='purchase'||action.startsWith('claim_'))reloadPlatform(); }
   return true;
  } catch (e) { notify(e instanceof Error ? e.message : '요청을 처리하지 못했습니다.','error'); reloadEngagement(); reloadPlatform(); return false; }
  finally { lock.current = false; setBusy(false); }
 },[userId, setEngagement, reloadEngagement, reloadPlatform, notify]);
 const track = useCallback((kind: string, target: string) => {
  if (!userId) return;
  const day = resource.data.day || new Intl.DateTimeFormat('en-CA',{timeZone:'Asia/Seoul',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date());
  const key = `${userId}:${day}:${kind}:${target}`;
  if (tracked.current.has(key)) return;
  tracked.current.add(key);
  void apiRequest('/api/kickx/engagement','POST',{action:'view',input:{kind,target}}).then(()=>{if(currentUser.current===userId)reloadEngagement();}).catch(()=>tracked.current.delete(key));
 },[userId,reloadEngagement,resource.data.day]);
 // Cross midnight/Tuesday without requiring a new browser session.
 useEffect(()=>{
  if(!resource.data.resetsAt) return;
  const timer=setTimeout(()=>{if(document.visibilityState==='visible')reloadEngagement();},Math.max(1000,Math.min(2147483647,Date.parse(resource.data.resetsAt)-Date.now()+1000)));
  return ()=>clearTimeout(timer);
 },[resource.data.resetsAt,reloadEngagement]);
 const value = useMemo(()=>({state,ready:!!userId&&resource.status==='ready',error:resource.status==='error',busy,reload:resource.reload,act,track}),[state,resource.status,resource.reload,userId,busy,act,track]);
 return <Context.Provider value={value}>{children}</Context.Provider>;
}
export function useEngagement() { const c=useContext(Context);if(!c)throw new Error('EngagementProvider is required');return c; }
export function useMissionView(kind: string, target: string | null, enabled = true) {
 const { track } = useEngagement();
 useEffect(()=>{if(enabled&&target)track(kind,target);},[kind,target,enabled,track]);
}
export function useLoadout(): Loadout { return useEngagement().state.loadout; }
