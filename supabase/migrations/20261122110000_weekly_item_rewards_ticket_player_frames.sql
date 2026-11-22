-- 1) Weekly missions: each completed mission can be claimed for 1,000P; clearing all six adds 4,000P
--    (the weekly maximum stays 10,000P). 2) Attendance recovery ticket costs 2,500P.
-- 3) Members can give each owned player their own frame (falls back to the equipped frame).

create table kickx_private.weekly_item_claims(
 user_id uuid not null references auth.users(id) on delete cascade,week date not null,mission text not null,
 claimed_at timestamptz not null default clock_timestamp(),primary key(user_id,week,mission));
alter table kickx_private.weekly_item_claims enable row level security;
revoke all on kickx_private.weekly_item_claims from public,anon,authenticated,service_role;

do $patch$ declare d text;begin
 d:=pg_get_functiondef('kickx_private.weekly_progress(uuid,date)'::regprocedure);
 if position($q$'claimed',(select exists(select 1 from kickx_private.weekly_claims where user_id=u and week=w)));$q$ in d)=0 then raise exception 'weekly_progress shape changed';end if;
 d:=replace(d,$q$'claimed',(select exists(select 1 from kickx_private.weekly_claims where user_id=u and week=w)));$q$,
  $q$'claimed',(select exists(select 1 from kickx_private.weekly_claims where user_id=u and week=w)),
 'claimedItems',(select coalesce(jsonb_agg(c.mission order by c.mission),'[]'::jsonb) from kickx_private.weekly_item_claims c where c.user_id=u and c.week=w));$q$);
 execute d;

 d:=pg_get_functiondef('public.kickx_engagement()'::regprocedure);
 if position($q$jsonb_build_object('reward',10000)$q$ in d)=0 then raise exception 'kickx_engagement shape changed';end if;
 d:=replace(d,$q$jsonb_build_object('reward',10000)$q$,$q$jsonb_build_object('reward',4000,'itemReward',1000)$q$);
 execute d;

 d:=pg_get_functiondef('public.kickx_engagement_action(text,jsonb)'::regprocedure);
 if position($q$if found then amount:=10000;end if;$q$ in d)=0 or position($q$ elsif p_action='purchase' then$q$ in d)=0 then raise exception 'kickx_engagement_action shape changed';end if;
 d:=replace(d,$q$if found then amount:=10000;end if;$q$,$q$if found then amount:=4000;end if;$q$);
 d:=replace(d,$q$ elsif p_action='purchase' then$q$,$q$ elsif p_action='claim_weekly_item' then
  progress:=kickx_private.weekly_progress(u,w);
  if not exists(select 1 from jsonb_array_elements(progress->'items') x where x->>'id'=p_input->>'mission' and (x->>'current')::int>=(x->>'target')::int) then raise exception 'MISSIONS_INCOMPLETE';end if;
  insert into kickx_private.weekly_item_claims(user_id,week,mission) values(u,w,p_input->>'mission') on conflict do nothing;
  if found then amount:=1000;end if;
 elsif p_action='purchase' then$q$);
 execute d;
end $patch$;

update kickx_private.shop_items set price=2500 where id='attendance-ticket';

create table kickx_private.player_frames(
 user_id uuid not null references auth.users(id) on delete cascade,player_id text not null,
 item_id text not null references kickx_private.shop_items(id),updated_at timestamptz not null default clock_timestamp(),
 primary key(user_id,player_id));
alter table kickx_private.player_frames enable row level security;
revoke all on kickx_private.player_frames from public,anon,authenticated,service_role;

create function public.kickx_player_frames() returns jsonb
language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_object_agg(f.player_id,f.item_id),'{}'::jsonb) from kickx_private.player_frames f where f.user_id=auth.uid() $$;

-- p_item null/empty clears the player's own frame. Only owned frames, only on players the member holds.
create function public.kickx_set_player_frame(p_player text,p_item text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare u uuid:=public.kickx_require_active_member();item text:=nullif(p_item,'');begin
 if p_player is null or length(p_player)>120 then raise exception 'INVALID_INPUT';end if;
 if item is null then delete from kickx_private.player_frames where user_id=u and player_id=p_player;return public.kickx_player_frames();end if;
 if not exists(select 1 from kickx_private.cosmetic_inventory inv join kickx_private.shop_items s on s.id=inv.item_id
  where inv.user_id=u and inv.item_id=item and inv.quantity>0 and s.category='frame') then raise exception 'ITEM_NOT_OWNED';end if;
 if not exists(select 1 from public.holdings h where h.user_id=u and h.player_id=p_player) then raise exception 'PLAYER_NOT_OWNED';end if;
 insert into kickx_private.player_frames(user_id,player_id,item_id) values(u,p_player,item)
 on conflict(user_id,player_id) do update set item_id=excluded.item_id,updated_at=clock_timestamp();
 return public.kickx_player_frames();
end $$;
revoke all on function public.kickx_player_frames(),public.kickx_set_player_frame(text,text) from public,anon;
grant execute on function public.kickx_player_frames(),public.kickx_set_player_frame(text,text) to authenticated;
