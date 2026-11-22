-- 1) New members start with 1,000,000P (existing wallets are unchanged).
-- 2) The weekly mission week now turns over on Tuesday 09:00 KST instead of 00:00.
--    Before 09:00 on Tuesday the previous week stays open (its day range includes that Tuesday);
--    match-based missions use the 09:00 boundary as well.
update public.kickx_policy set initial_points=1000000 where id=true;

create function kickx_private.mission_now() returns timestamp language sql stable set search_path='' as $$
 select now() at time zone 'Asia/Seoul' $$;
create function kickx_private.mission_week_now() returns date language sql stable set search_path='' as $$
 select kickx_private.mission_week(kickx_private.mission_today()-case when extract(isodow from kickx_private.mission_today())=2
  and kickx_private.mission_now()::time<time '09:00' then 1 else 0 end) $$;

do $patch$ declare d text;f text;begin
 foreach f in array array['public.kickx_engagement()','public.kickx_engagement_action(text,jsonb)'] loop
  d:=pg_get_functiondef(f::regprocedure);
  if position('w date:=kickx_private.mission_week(d);' in d)=0 then raise exception '% shape changed',f;end if;
  d:=replace(d,'w date:=kickx_private.mission_week(d);','w date:=kickx_private.mission_week_now();');
  execute d;
 end loop;
 d:=pg_get_functiondef('kickx_private.weekly_progress(uuid,date)'::regprocedure);
 if position($q$f.starts_at>=(w::timestamp at time zone 'Asia/Seoul') and f.starts_at<((w+7)::timestamp at time zone 'Asia/Seoul')$q$ in d)=0
  or position($q$'endsAt',((w+7)::timestamp at time zone 'Asia/Seoul')$q$ in d)=0 then raise exception 'weekly_progress shape changed';end if;
 d:=replace(d,$q$f.starts_at>=(w::timestamp at time zone 'Asia/Seoul') and f.starts_at<((w+7)::timestamp at time zone 'Asia/Seoul')$q$,
  $q$f.starts_at>=((w::timestamp+interval '9 hours') at time zone 'Asia/Seoul') and f.starts_at<(((w+7)::timestamp+interval '9 hours') at time zone 'Asia/Seoul')$q$);
 d:=replace(d,$q$'endsAt',((w+7)::timestamp at time zone 'Asia/Seoul')$q$,$q$'endsAt',(((w+7)::timestamp+interval '9 hours') at time zone 'Asia/Seoul')$q$);
 -- Day-based counts include the closing Tuesday so activity before 09:00 still counts for the open week.
 d:=replace(d,'day<w+7','day<=w+7');
 execute d;
end $patch$;
