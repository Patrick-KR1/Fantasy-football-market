-- Disposable CI: site visits check in once, respect KST boundaries and never award cash twice.
begin;
create or replace function kickx_private.mission_today() returns date language sql stable set search_path='' as $$select date '2026-11-23'$$;
insert into auth.users(id) values('00000000-0000-0000-0000-000000000230'),('00000000-0000-0000-0000-000000000231'),('00000000-0000-0000-0000-000000000232');
insert into public.profiles(id,nickname,created_at) select id,'Attendance '||right(id::text,3),'2026-01-01' from auth.users where id in('00000000-0000-0000-0000-000000000230','00000000-0000-0000-0000-000000000231','00000000-0000-0000-0000-000000000232');
insert into public.member_restrictions(user_id,suspended_until,reason) values('00000000-0000-0000-0000-000000000231',now()+interval '1 day','CI suspension');
select kickx_private.ensure_mission_day('00000000-0000-0000-0000-000000000232','2026-11-23');
update kickx_private.mission_days set choices=array['fixtures','watch'] where user_id='00000000-0000-0000-0000-000000000232';
insert into kickx_private.mission_events(user_id,day,kind,target) values('00000000-0000-0000-0000-000000000232','2026-11-23','fixtures','schedule'),('00000000-0000-0000-0000-000000000232','2026-11-23','watch','CI player');
set local role authenticated;
set local request.jwt.claim.sub='00000000-0000-0000-0000-000000000230';
do $$declare s jsonb;begin
 for i in 1..4 loop
  s:=public.kickx_engagement();
  if s#>>'{daily,items,0,current}'<>'1' or jsonb_array_length(s->'attendance')<>1 then raise exception 'Visit attendance missing or duplicated';end if;
 end loop;
 if exists(select 1 from public.wallets) then raise exception 'Attendance visit must not open or fund wallet';end if;
end $$;
set local request.jwt.claim.sub='00000000-0000-0000-0000-000000000231';
do $$begin if public.kickx_engagement()#>>'{daily,items,0,current}'<>'0' then raise exception 'Suspended member auto-checked in';end if;end $$;
set local request.jwt.claim.sub='00000000-0000-0000-0000-000000000232';
do $$declare s jsonb:=public.kickx_engagement();begin
 if s#>>'{daily,cleared}'<>'true' then raise exception 'Auto attendance did not finish previously completed daily activities';end if;
 perform public.kickx_engagement_action('claim_daily');
 perform public.kickx_engagement();perform public.kickx_engagement_action('claim_daily');
 if (public.kickx_member_data()->>'points')::bigint<>1301000 then raise exception 'Auto attendance duplicated mission rewards';end if;
end $$;
reset role;
create or replace function kickx_private.mission_today() returns date language sql stable set search_path='' as $$select date '2026-11-24'$$;
set local role authenticated;
set local request.jwt.claim.sub='00000000-0000-0000-0000-000000000230';
do $$declare s jsonb:=public.kickx_engagement();begin
 if s->>'day'<>'2026-11-24' or s#>>'{weekly,week}'<>'2026-11-24' or s#>>'{weekly,items,5,current}'<>'1' then raise exception 'Tuesday reset/check-in boundary wrong';end if;
 perform public.kickx_engagement();
end $$;
reset role;
do $$begin
 if (select count(*) from kickx_private.attendance where user_id='00000000-0000-0000-0000-000000000230')<>2 then raise exception 'Visits did not produce exactly two distinct dates';end if;
 if exists(select 1 from kickx_private.attendance where user_id='00000000-0000-0000-0000-000000000231') then raise exception 'Suspension attendance leaked';end if;
 if exists(select 1 from kickx_private.attendance where recovered) then raise exception 'Automatic attendance must be real attendance';end if;
end $$;
rollback;
