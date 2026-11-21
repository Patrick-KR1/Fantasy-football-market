-- Disposable CI only. All synthetic users, matches and clock overrides roll back.
begin;
create or replace function kickx_private.mission_today() returns date language sql stable set search_path='' as $$select date '2026-11-23'$$;
update public.kickx_policy set version='prototype-v1',club_competitions_enabled=false;
insert into auth.users(id) select ('00000000-0000-0000-0000-0000000002'||n)::uuid from generate_series(10,14)n;
insert into public.profiles(id,nickname,created_at) select id,'Mission '||right(id::text,3),'2026-01-01' from auth.users where id::text like '%00000000021_';
insert into public.leagues(id,name) values('bsd-1','Mission League') on conflict do nothing;
insert into public.teams(id,name,league_id) values('mission-home','Mission Home','bsd-1'),('mission-away','Mission Away','bsd-1');
insert into public.players(id,name,provider,position,team_id) values('mission-GK','Mission GK','bsd','GK','mission-home');
insert into public.player_market_snapshots(id,price,pricing_rule_version,pricing_status) values('mission-GK',80000,'prototype-v1','ready');
create function pg_temp.eng_error(command text,expected text) returns void language plpgsql as $$begin
 begin execute command;exception when others then if sqlerrm=expected or sqlstate=expected then return;else raise;end if;end;
 raise exception 'Expected % from %',expected,command;
end $$;
create function pg_temp.eng_buy(id text) returns void language plpgsql as $$declare q jsonb;begin
 q:=public.kickx_quote(id,'buy');perform public.kickx_trade((q->>'id')::uuid,gen_random_uuid());end $$;
do $$begin
 if kickx_private.mission_week(date '2026-11-23')<>date '2026-11-17' or kickx_private.mission_week(date '2026-11-24')<>date '2026-11-24'
 or kickx_private.mission_week(date '2026-11-22')<>date '2026-11-17' then raise exception 'Tuesday boundary wrong';end if;
end $$;
set local role authenticated;
set local request.jwt.claim.sub='00000000-0000-0000-0000-000000000210';
select public.kickx_open_wallet();select public.kickx_engagement();
do $$declare a jsonb:=public.kickx_engagement();begin
 if a#>'{daily,items}'<>public.kickx_engagement()#>'{daily,items}' or jsonb_array_length(a#>'{daily,items}')<>3 then raise exception 'Daily assignment unstable';end if;
 if a#>>'{daily,items,0,current}'<>'1' then raise exception 'Site visit did not automatically check attendance';end if;
 if (select (x->>'price')::int from jsonb_array_elements(a->'catalog') x where x->>'id'='attendance-ticket')<>5000 then raise exception 'Recovery ticket price must be 5000';end if;
 perform pg_temp.eng_error('select * from kickx_private.mission_events','42501');
 perform pg_temp.eng_error($q$select kickx_private.mission_event(auth.uid(),'fixtures','forged')$q$,'42501');
 perform pg_temp.eng_error($q$select public.kickx_engagement_action('claim_daily')$q$,'MISSIONS_INCOMPLETE');
 perform pg_temp.eng_error($q$select public.kickx_mission_view('ai_report','mission-GK:not-real')$q$,'REPORT_NOT_READY');
 perform pg_temp.eng_error($q$select public.kickx_mission_view('price','not-real')$q$,'INVALID_TARGET');
end $$;
reset role;
update kickx_private.mission_days set choices=array['fixtures','watch'] where user_id='00000000-0000-0000-0000-000000000210';
set local role authenticated;
select public.kickx_engagement_action('attendance');select public.kickx_engagement_action('attendance');
select public.kickx_mission_view('fixtures','schedule');select public.kickx_mission_view('fixtures','schedule');
insert into public.watchlists(user_id,player_id) values(auth.uid(),'mission-GK');
select public.kickx_engagement_action('claim_daily');select public.kickx_engagement_action('claim_daily');
do $$declare m jsonb:=public.kickx_member_data();begin
 if (m->>'points')::bigint<>1301000 or (m->>'returnRate')::numeric<>0 or (m->>'realizedProfit')::numeric<>0 then raise exception 'Reward duplicated or counted as trading profit';end if;
end $$;
select public.kickx_engagement_action('purchase','{"itemId":"nameplate-circuit","requestId":"00000000-0000-0000-0001-000000000001"}');
select public.kickx_engagement_action('purchase','{"itemId":"nameplate-circuit","requestId":"00000000-0000-0000-0001-000000000001"}');
select public.kickx_engagement_action('equip','{"category":"nameplate","itemId":"nameplate-circuit"}');
select public.kickx_engagement_action('equip','{"category":"faces","enabled":true}');
do $$declare e jsonb:=public.kickx_engagement();m jsonb:=public.kickx_member_data();begin
 if e#>>'{inventory,nameplate-circuit}'<>'1' or e#>>'{loadout,faces}'<>'true' or e#>>'{loadout,nameplate}'<>'nameplate-circuit' then raise exception 'Inventory/equip failed';end if;
 if (m->>'points')::bigint<>1283000 or (m->>'returnRate')::numeric<>0 then raise exception 'Shop double-charged or distorted ROI';end if;
 if public.kickx_nameplates(array[auth.uid()])->>auth.uid()::text<>'nameplate-circuit' then raise exception 'Public plate missing';end if;
 perform pg_temp.eng_error($q$select public.kickx_engagement_action('purchase','{"itemId":"nameplate-circuit","requestId":"00000000-0000-0000-0001-000000000002"}')$q$,'ITEM_OWNED');
 perform pg_temp.eng_error($q$select public.kickx_engagement_action('purchase','{"itemId":"attendance-ticket","requestId":"00000000-0000-0000-0001-000000000001"}')$q$,'REQUEST_REUSED');
 perform pg_temp.eng_error($q$select public.kickx_engagement_action('equip','{"category":"pitch","itemId":"nameplate-circuit"}')$q$,'ITEM_NOT_OWNED');
end $$;
select public.kickx_engagement_action('purchase','{"itemId":"attendance-ticket","requestId":"00000000-0000-0000-0001-000000000003"}');
select public.kickx_engagement_action('recover','{"day":"2026-11-17"}');
select public.kickx_engagement_action('recover','{"day":"2026-11-17"}');
do $$declare e jsonb:=public.kickx_engagement();begin
 if e#>>'{inventory,attendance-ticket}'<>'0' then raise exception 'Recovery ticket consumed twice';end if;
 perform pg_temp.eng_error($q$select public.kickx_engagement_action('recover','{"day":"2026-11-24"}')$q$,'INVALID_RECOVERY_DAY');
 perform pg_temp.eng_error($q$select public.kickx_engagement_action('recover','{"day":"2026-11-16"}')$q$,'INVALID_RECOVERY_DAY');
 perform pg_temp.eng_error($q$select public.kickx_engagement_action('recover','{"day":"2026-11-18"}')$q$,'NO_RECOVERY_TICKET');
end $$;
reset role;
do $$begin
 if (select count(*) from kickx_private.attendance where user_id='00000000-0000-0000-0000-000000000210')<>2 then raise exception 'Attendance replay duplicated days';end if;
 if (select count(*) from kickx_private.mission_events where user_id='00000000-0000-0000-0000-000000000210' and kind='fixtures')<>1 then raise exception 'Refresh inflated activity';end if;
 if exists(select 1 from kickx_private.mission_days where user_id='00000000-0000-0000-0000-000000000210' and day='2026-11-17' and cleared_at is not null) then raise exception 'Recovery retroactively cleared daily';end if;
end $$;
-- A one-player pool guarantees a duplicate and proves owned players stay eligible.
set local role authenticated;select pg_temp.eng_buy('mission-GK');
do $$declare r jsonb;before bigint:=(select balance from public.wallets);begin
 r:=public.kickx_draw('00000000-0000-0000-0002-000000000001');
 if r->>'status'<>'duplicate' or (r->>'pool_size')::int<>1 or (r->>'compensation')::bigint<>78400 then raise exception 'Duplicate draw policy wrong: %',r;end if;
 if (select balance from public.wallets)<>before-100000+78400 then raise exception 'Draw settlement wrong';end if;
 if r<>public.kickx_draw('00000000-0000-0000-0002-000000000001') then raise exception 'Draw retry rerolled';end if;
 perform pg_temp.eng_error($q$select public.kickx_draw('00000000-0000-0000-0002-000000000002')$q$,'DRAW_DAILY_LIMIT');
end $$;
reset role;
-- Fill another squad and draw the only eligible extra GK: cannot evade GK capacity.
insert into public.players(id,name,provider,position,team_id)
 select 'mission-'||p||'-'||n,'Mission '||p||n,'bsd',p,'mission-home'
 from(values('DF',4),('MF',3),('FW',3))x(p,cap) cross join lateral generate_series(1,cap)n;
insert into public.player_market_snapshots(id,price,pricing_rule_version,pricing_status)
 select id,10000,'prototype-v1','ready' from public.players where id like 'mission-%' and id<>'mission-GK';
set local role authenticated;
set local request.jwt.claim.sub='00000000-0000-0000-0000-000000000211';select public.kickx_open_wallet();
select pg_temp.eng_buy(id) from public.players where id like 'mission-%' order by id;
reset role;
update public.player_market_snapshots set pricing_status='pending' where id like 'mission-%';
insert into public.players(id,name,provider,position,team_id) values('mission-GK-new','New GK','bsd','GK','mission-away');
insert into public.player_market_snapshots(id,price,pricing_rule_version,pricing_status) values('mission-GK-new',140000,'prototype-v1','ready');
set local role authenticated;
do $$declare r jsonb;before bigint:=(select balance from public.wallets);assets bigint;receipt jsonb;begin
 assets:=(public.kickx_member_data()->>'totalAssets')::bigint;r:=public.kickx_draw('00000000-0000-0000-0002-000000000003');
 if r->>'player_id'<>'mission-GK-new' or r->>'status'<>'pending' then raise exception 'Uniform pool wrong';end if;
 if (public.kickx_member_data()->>'totalAssets')::bigint<>assets or (public.kickx_member_data()->>'pendingDrawAssets')::bigint<>100000 then raise exception 'Pending draw lost assets';end if;
 perform set_config('eng.draw',r->>'id',true);
 perform pg_temp.eng_error(format('select public.kickx_place_draw(%L,null)',r->>'id'),'DRAW_BENCH_REQUIRED');
 perform pg_temp.eng_error(format('select public.kickx_place_draw(%L,''mission-DF-1'')',r->>'id'),'INVALID_BENCH_SELECTION');
 receipt:=public.kickx_place_draw((r->>'id')::uuid,'mission-GK');
 perform public.kickx_place_draw((r->>'id')::uuid,'mission-GK');
 if (select balance from public.wallets)<>before-100000 then raise exception 'Placement charged twice';end if;
 if (select count(*) from public.holdings where bench_started_at is null)<>11 or (select count(*) from public.holdings where bench_started_at is not null)<>1 then raise exception 'Full squad bench placement failed';end if;
 if (public.kickx_member_data()->>'totalAssets')::bigint<>assets+40000 or (public.kickx_member_data()->>'pendingDrawAssets')::bigint<>0 then raise exception 'Placed assets wrong';end if;
 if (select count(*) from public.trades where execution_reason='draw')<>1 then raise exception 'Placement replay created trade';end if;
end $$;
reset role;
-- On-match ownership, distinct appearances, high score, and a late purchase exclusion.
insert into public.fixtures(id,league_id,home_team_id,away_team_id,starts_at,status,finished_observed_at)
 values('mission-match','bsd-1','mission-home','mission-away','2026-11-21 12:00+00','FT','2026-11-21 14:00+00');
update kickx_private.roster_history set recorded_at='2026-11-20' where user_id='00000000-0000-0000-0000-000000000211';
insert into public.player_match_records(player_id,fixture_id,played_at,opponent,result,minutes,goals,assists,performance,rule_version)
 select id,'mission-match','2026-11-21 12:00+00','Away','W',90,0,0,case when id='mission-MF-1' then 10 else 5 end,'prototype-v1'
 from public.players where id in('mission-GK-new','mission-DF-1','mission-DF-2','mission-DF-3','mission-DF-4','mission-MF-1','mission-MF-2');
insert into public.performance_results(player_id,fixture_id,score,status,rule_version,input_hash,breakdown,warnings)
 select player_id,fixture_id,performance,'ready','prototype-v1','mission-test','[]','[]' from public.player_match_records where fixture_id='mission-match';
update kickx_private.roster_history set recorded_at='2026-11-22' where user_id='00000000-0000-0000-0000-000000000211' and player_id='mission-MF-2';
do $$declare p jsonb:=kickx_private.weekly_progress('00000000-0000-0000-0000-000000000211','2026-11-17');begin
 if p#>>'{items,0,current}'<>'6' or p#>>'{items,1,current}'<>'1' or (p->>'international')::boolean then raise exception 'Ownership/score weekly qualification wrong: %',p;end if;
end $$;
update kickx_private.roster_history set recorded_at='2026-11-20' where user_id='00000000-0000-0000-0000-000000000211' and player_id='mission-MF-2';
insert into kickx_private.attendance(user_id,day) select '00000000-0000-0000-0000-000000000211',date '2026-11-17'+n from generate_series(0,6)n on conflict do nothing;
insert into kickx_private.mission_days(user_id,day,choices,cleared_at) select '00000000-0000-0000-0000-000000000211',date '2026-11-17'+n,array['fixtures','watch'],now() from generate_series(0,4)n on conflict do nothing;
insert into kickx_private.mission_events(user_id,day,kind,target) select '00000000-0000-0000-0000-000000000211','2026-11-23','comment','weekly-'||n from generate_series(1,10)n;
insert into kickx_private.mission_events(user_id,day,kind,target) values('00000000-0000-0000-0000-000000000211','2026-11-23','sell','manual-test');
set local role authenticated;
do $$declare before bigint:=(select balance from public.wallets);begin
 perform public.kickx_engagement_action('claim_weekly');perform public.kickx_engagement_action('claim_weekly');
 if (select balance from public.wallets)<>before+10000 then raise exception 'Weekly reward duplicated';end if;
end $$;
set local request.jwt.claim.sub='00000000-0000-0000-0000-000000000212';
do $$begin
 perform pg_temp.eng_error(format('select public.kickx_place_draw(%L,''mission-GK'')',current_setting('eng.draw')),'DRAW_NOT_FOUND');
 if public.kickx_engagement()#>'{draw,history}'<>'[]' then raise exception 'Other account draw leaked';end if;
end $$;
reset role;
-- The exact Fri~Mon detection, with canceled/postponed matches ignored.
do $$declare p jsonb:=kickx_private.weekly_progress('00000000-0000-0000-0000-000000000212','2026-11-24');begin
 if not (p->>'international')::boolean or p#>>'{items,0,id}'<>'ai_report' or p#>>'{items,1,id}'<>'price' then raise exception 'International replacement failed';end if;
end $$;
insert into public.fixtures(id,league_id,home_team_id,away_team_id,starts_at,status) values('mission-tuesday','bsd-1','mission-home','mission-away','2026-11-24 10:00+00','NS'),('mission-cancel','bsd-1','mission-home','mission-away','2026-11-27 10:00+00','CANC');
do $$begin if not kickx_private.international_week('2026-11-24') then raise exception 'Non-weekend/canceled match triggered regular mode';end if;end $$;
insert into public.fixtures(id,league_id,home_team_id,away_team_id,starts_at,status) values('mission-weekend','bsd-1','mission-home','mission-away','2026-11-30 14:59+00','NS');
do $$begin if kickx_private.international_week('2026-11-24') then raise exception 'Monday KST match missed';end if;end $$;
-- Real view/write receipts; repeated refreshes and edits cannot increase counters.
insert into public.player_analyses(id,fixture_id,body,source_updated_at,status,prompt_version)
 values('mission-GK','mission-match','{"performance":"저장된 경기 기록을 바탕으로 작성한 설명입니다."}',now(),'ready','match-report-points-v5');
set local role authenticated;
select public.kickx_open_wallet();select public.kickx_mission_view('ai_report','mission-GK:mission-match');
select public.kickx_mission_view('ai_report','mission-GK:mission-match');
select public.kickx_mission_view('price','mission-GK');select public.kickx_mission_view('price','mission-GK');
reset role;
insert into public.community_posts(id,author_id,scope,target,title,body,request_id) values
 ('00000000-0000-0000-0003-000000000001','00000000-0000-0000-0000-000000000212','player','mission-GK','Player post','A valid new player post body.',gen_random_uuid()),
 ('00000000-0000-0000-0003-000000000002','00000000-0000-0000-0000-000000000212','club','mission-home','Club post','A valid new club post body.',gen_random_uuid());
insert into public.community_comments(post_id,author_id,body,request_id) values('00000000-0000-0000-0003-000000000001','00000000-0000-0000-0000-000000000212','Community comment',gen_random_uuid());
update public.community_posts set title='Edited player post' where id='00000000-0000-0000-0003-000000000001';
do $$begin
 if (select count(*) from kickx_private.mission_events where user_id='00000000-0000-0000-0000-000000000212' and kind in('ai_report','price'))<>2 then raise exception 'View receipt duplicates';end if;
 if (select count(*) from kickx_private.mission_events where user_id='00000000-0000-0000-0000-000000000212' and kind in('player_post','club_post','comment'))<>3 then raise exception 'Community receipts missing or edit counted';end if;
end $$;
-- Random rewards cannot bypass the existing on-match starter/trading restriction.
insert into public.fixtures(id,league_id,home_team_id,away_team_id,starts_at,status)
 values('mission-locked','bsd-1','mission-home','mission-away',clock_timestamp()+interval '20 minutes','NS');
set local role authenticated;
set local request.jwt.claim.sub='00000000-0000-0000-0000-000000000214';select public.kickx_open_wallet();
do $$declare r jsonb;begin
 r:=public.kickx_draw('00000000-0000-0000-0002-000000000004');
 perform pg_temp.eng_error(format('select public.kickx_place_draw(%L,null)',r->>'id'),'DRAW_LOCKED_USE_BENCH');
 perform public.kickx_place_draw((r->>'id')::uuid,r->>'player_id');
 if not exists(select 1 from public.holdings where player_id='mission-GK-new' and bench_reason='draw') then raise exception 'Locked player not safely benched';end if;
end $$;
set local request.jwt.claim.sub='00000000-0000-0000-0000-000000000213';select public.kickx_open_wallet();
reset role;update public.wallets set balance=0 where user_id='00000000-0000-0000-0000-000000000213';
set local role authenticated;
do $$begin
 perform pg_temp.eng_error($q$select public.kickx_draw(gen_random_uuid())$q$,'INSUFFICIENT_POINTS');
 if public.kickx_engagement()#>'{draw,history}'<>'[]' then raise exception 'Failed draw consumed daily limit';end if;
end $$;
reset role;
set local role anon;
do $$begin
 if jsonb_array_length(public.kickx_shop_catalog()->'catalog')<>41 or (public.kickx_shop_catalog()-'catalog'-'poolSize')<>'{}'::jsonb then raise exception 'Public catalog missing or includes private fields';end if;
 perform pg_temp.eng_error('select public.kickx_engagement()','42501');
 perform pg_temp.eng_error($q$select public.kickx_draw(gen_random_uuid())$q$,'42501');
 if public.kickx_nameplates(array['00000000-0000-0000-0000-000000000210'::uuid])->>'00000000-0000-0000-0000-000000000210'<>'nameplate-circuit' then raise exception 'Public plate read failed';end if;
end $$;
reset role;
rollback;
