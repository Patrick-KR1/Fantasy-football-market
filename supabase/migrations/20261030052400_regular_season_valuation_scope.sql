create or replace function public.kickx_report_baseline(p_player text,p_position text,p_reference jsonb,p_parameters jsonb)
returns jsonb language plpgsql immutable set search_path='' as $$
declare g jsonb;o jsonb;cohort jsonb;n integer;mu numeric;b numeric;pct numeric;v bigint;season integer;size integer;lo integer;hi integer;mid integer;below integer;through integer;begin
 g:=p_reference#>array['groups',p_position];o:=p_reference#>array['players',p_player,p_position];cohort:=g->'baselines';
 if p_reference->>'status' is distinct from 'ready' or g is null or jsonb_array_length(cohort)=0 then return null;end if;
 n:=coalesce((o->>'n')::integer,0);mu:=(g->>'mean')::numeric;season:=(p_reference->>'season')::integer;
 b:=round((coalesce((o->>'sum')::numeric,0)+(p_parameters->>'lambda')::numeric*mu)/(n+(p_parameters->>'lambda')::numeric),10);
 -- The frozen position cohort is sorted. Two binary searches preserve tied midranks.
 size:=jsonb_array_length(cohort);lo:=0;hi:=size;
 while lo<hi loop mid:=(lo+hi)/2;if (cohort->>mid)::numeric<b then lo:=mid+1;else hi:=mid;end if;end loop;below:=lo;
 lo:=0;hi:=size;
 while lo<hi loop mid:=(lo+hi)/2;if (cohort->>mid)::numeric<=b then lo:=mid+1;else hi:=mid;end if;end loop;through:=lo;
 pct:=(below+0.5*(through-below))/size;
 v:=round((p_parameters->>'initialMin')::numeric+((p_parameters->>'initialMax')::numeric-(p_parameters->>'initialMin')::numeric)*pct);
 return jsonb_build_object('source',case when n>0 then 'previous-season' else 'position-prior' end,'season',season,'gameCount',n,
 'meanScore',case when n>0 then (o->>'sum')::numeric/n else null end,'seedScore',b,'percentile',pct,'price',v,
 'lower',g->'lower','upper',g->'upper','referenceHash',p_reference->>'hash','fixtures',coalesce(o->'fixtures','[]'),
 'warnings',case when n>0 then '[]'::jsonb else '["PREVIOUS_SEASON_PLAYER_UNAVAILABLE"]'::jsonb end);
end $$;

-- Compute match-clock evidence once per changed source, then read a small cached integer.
alter table public.fixtures add column if not exists observed_duration_minutes integer check(observed_duration_minutes between 90 and 180);
create or replace function public.kickx_duration_evidence(p_stats jsonb,p_incidents jsonb) returns integer language sql immutable set search_path='' set jit=off as $$
 with stats as materialized(select x->>'player_id' player_id,case when jsonb_typeof(x->'minutes_played')='number' then (x->>'minutes_played')::numeric end n from jsonb_array_elements(coalesce(p_stats->'player_stats','[]'))x),
 events as materialized(select x from jsonb_array_elements(coalesce(p_incidents->'incidents','[]'))x),
 inferred as(select (e.x->>'minute')::numeric+case when (e.x->>'minute')::numeric in(45,90)and jsonb_typeof(e.x->'added_time')='number' then (e.x->>'added_time')::numeric else 0 end+s.n n
 from events e join stats s on s.player_id=e.x->>'player_in_id' where e.x->>'type'='substitution' and jsonb_typeof(e.x->'minute')='number' and s.n>0
 and (select count(*)from events q where q.x->>'type'='substitution' and q.x->>'player_in_id'=s.player_id)=1
 and not exists(select 1 from events q where q.x->>'type'='substitution' and q.x->>'player_out_id'=s.player_id)),
 values_at as(select n from stats union all select n from inferred where n between 90 and 120),
 ordered as(select n,lead(n)over(order by n desc) next_n from values_at where n between 90 and 180 and n=trunc(n))
 select coalesce(max(n)filter(where next_n>=n-2),90)::integer from ordered
$$;
revoke all on function public.kickx_duration_evidence(jsonb,jsonb) from public,anon,authenticated;
grant execute on function public.kickx_duration_evidence(jsonb,jsonb) to service_role;
create or replace function public.kickx_cache_fixture_duration() returns trigger language plpgsql set search_path='' as $$begin
 if tg_op='UPDATE' and (new.player_stats,new.incidents)is not distinct from(old.player_stats,old.incidents)then return new;end if;
 if jsonb_typeof(new.player_stats->'player_stats')='array' and jsonb_array_length(new.player_stats->'player_stats')>0 then
  update public.fixtures set observed_duration_minutes=public.kickx_duration_evidence(new.player_stats,new.incidents)where id=new.fixture_id;
 end if;
 return new;
end $$;
revoke all on function public.kickx_cache_fixture_duration() from public,anon,authenticated;
drop trigger if exists cache_fixture_duration on public.football_event_sources;
create trigger cache_fixture_duration after insert or update of player_stats,incidents on public.football_event_sources for each row execute function public.kickx_cache_fixture_duration();
update public.fixtures f set observed_duration_minutes=public.kickx_duration_evidence(s.player_stats,s.incidents)from public.football_event_sources s where s.fixture_id=f.id and jsonb_typeof(s.player_stats->'player_stats')='array' and jsonb_array_length(s.player_stats->'player_stats')>0;
create or replace function public.kickx_observed_fixture_minutes(p_fixture text) returns integer language sql stable set search_path='' as $$
 select case when f.observed_duration_minutes is not null then f.observed_duration_minutes else(
  with values_at as(select case when jsonb_typeof(stats->'minutes_played')='number' then(stats->>'minutes_played')::numeric end n from public.football_match_stats where fixture_id=p_fixture),
  ordered as(select n,lead(n)over(order by n desc)next_n from values_at where n between 90 and 180 and n=trunc(n))select coalesce(max(n)filter(where next_n>=n-2),90)::integer from ordered
 )end from public.fixtures f where f.id=p_fixture
$$;

-- League IDs also contain relegation playoffs. Missing scope stays unverified.
create or replace function public.kickx_regular_fixture(p_fixture text) returns boolean language sql stable set search_path='' as $$
 select case when f.league_id is null then null when f.league_id not in('bsd-1','bsd-3','bsd-4','bsd-5','bsd-6')then false
 when regexp_replace(lower(coalesce(nullif(f.stage,''),nullif(s.detail->>'stage',''),'')),'[^a-z]','','g') in('leaguephase','regularseason')then true
 when regexp_replace(lower(coalesce(nullif(f.stage,''),nullif(s.detail->>'stage',''),'')),'[^a-z]','','g')~'qualification|final|playoff|relegation|promotion|knockout|roundof'then false
 when coalesce(nullif(f.stage,''),nullif(s.detail->>'stage',''))is null and coalesce(f.round_label,s.detail->>'round_label','')~*'^(league phase|regular season)\y'then true else null end
 from public.fixtures f left join public.football_event_sources s on s.fixture_id=f.id where f.id=p_fixture
$$;
revoke all on function public.kickx_regular_fixture(text) from public,anon,authenticated;
grant execute on function public.kickx_regular_fixture(text) to service_role;
create or replace function public.kickx_calculation_sources(p_player text)
returns table(fixture_id text,source_hash text,cached boolean) language sql stable set search_path='' as $$
 select m.fixture_id,h.signature,coalesce(r.rule_version=p.version and r.source_hash=h.signature,false)
 from public.football_match_stats m join public.fixtures f on f.id=m.fixture_id
 left join public.football_event_sources s on s.fixture_id=f.id
 left join public.performance_results r on r.player_id=m.player_id and r.fixture_id=m.fixture_id
 cross join public.kickx_policy p
 cross join lateral(select case when p.version='report-v3' and public.kickx_regular_fixture(f.id) is distinct from true then md5((md5(jsonb_build_array(m.updated_at,f.updated_at,s.updated_at,p.version,p.club_competitions_enabled,case when p.version='report-v3' then public.kickx_observed_fixture_minutes(f.id) end,'scoring-cache-v1')::text))||':regular-season-scope') when p.version='report-v3' and s.incidents @? '$.incidents[*] ? (@.type == "varDecision" && (@.decision == "cardUpgrade" || @.decision == "redCardGiven"))' then md5((md5(jsonb_build_array(m.updated_at,f.updated_at,s.updated_at,p.version,p.club_competitions_enabled,case when p.version='report-v3' then public.kickx_observed_fixture_minutes(f.id) end,'scoring-cache-v1')::text))||':var-terminal-20261030') else md5(jsonb_build_array(m.updated_at,f.updated_at,s.updated_at,p.version,p.club_competitions_enabled,case when p.version='report-v3' then public.kickx_observed_fixture_minutes(f.id) end,'scoring-cache-v1')::text) end as signature) h
 where m.player_id=p_player
$$;

create or replace function public.kickx_publish_calculation(p_actor uuid,p_player text,p_hash text,p_expected jsonb,p_results jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare p public.kickx_policy%rowtype;r jsonb;current_hash jsonb;enriched jsonb;plan jsonb;
 old_value bigint;value_now bigint;latest numeric;price_changed boolean;withheld boolean:=false;
 old_plan jsonb;old_ready boolean;old_pricing_status text;
begin
 if p_actor is not null and not exists(select 1 from public.user_roles where user_id=p_actor and role='admin') then raise exception 'ADMIN_REQUIRED';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('kickx:bsd-import',0));perform public.kickx_economy_lock();
 select * into strict p from public.kickx_policy;
 if p.version='prototype-v1' then return public.kickx_publish_calculation_v1(p_actor,p_player,p_hash,p_expected,p_results);end if;
 if p.version not in('form-v2','report-v3') then raise exception 'RULE_VERSION_MISMATCH';end if;
 if (p.club_competitions_enabled or p.version='report-v3') and not public.kickx_market_eligible(p_player) then delete from public.calculation_queue where player_id=p_player;return jsonb_build_object('unchanged',true,'outsideMarketScope',true);end if;
 if not exists(select 1 from public.players where id=p_player and provider='bsd') then raise exception 'INVALID_TARGET';end if;
 if jsonb_typeof(p_results) is distinct from 'array' or p_hash is null or p_hash='' then raise exception 'INVALID_INPUT';end if;
 select coalesce(jsonb_agg(jsonb_build_object('fixture',m.fixture_id,'statsAt',m.updated_at,'sourceAt',s.updated_at,'fixtureAt',f.updated_at) order by m.fixture_id),'[]') into current_hash from public.football_match_stats m join public.fixtures f on f.id=m.fixture_id left join public.football_event_sources s on s.fixture_id=f.id where m.player_id=p_player;
 select coalesce(jsonb_agg(jsonb_build_object('fixture',e.fixture,'statsAt',e."statsAt",'sourceAt',e."sourceAt",'fixtureAt',e."fixtureAt") order by e.fixture),'[]') into p_expected from jsonb_to_recordset(p_expected) as e(fixture text,"statsAt" timestamptz,"sourceAt" timestamptz,"fixtureAt" timestamptz);
 if current_hash is distinct from p_expected then raise exception 'SOURCE_CHANGED';end if;
 if jsonb_array_length(p_results)<>jsonb_array_length(current_hash) or
 (select count(distinct value->>'fixtureId') from jsonb_array_elements(p_results))<>jsonb_array_length(p_results) or
 exists(select 1 from jsonb_array_elements(p_results) x where
  not exists(select 1 from public.football_match_stats m where m.player_id=p_player and m.fixture_id=x->>'fixtureId') or
  x->>'ruleVersion' is distinct from p.version or x->>'status' is null or x->>'status' not in('ready','provisional','blocked','not-played') or
  jsonb_typeof(x->'breakdown') is distinct from 'array' or jsonb_typeof(x->'warnings') is distinct from 'array' or
  (x->>'status' in('ready','provisional') and (jsonb_typeof(x->'score') is distinct from 'number' or abs((x->>'score')::numeric)>10000)) or
  (x->>'status' in('blocked','not-played') and x->>'score' is not null)) then raise exception 'INVALID_INPUT';end if;
 if exists(select 1 from jsonb_array_elements(p_results) x join public.football_match_stats m on m.player_id=p_player and m.fixture_id=x->>'fixtureId' join public.fixtures f on f.id=m.fixture_id left join public.football_event_sources s on s.fixture_id=f.id
 where x->>'status' in('ready','provisional') and ((f.status not in ('FT','AET','PEN') or (not p.club_competitions_enabled and f.status<>'FT')) or f.starts_at>clock_timestamp() or coalesce((m.stats->>'minutes_played')::numeric,0)<=0 or (m.stats->>'minutes_played')::numeric>case when p.club_competitions_enabled and (f.status='AET' or s.detail->'extra_time_score' is not null and s.detail->'extra_time_score'<>'null'::jsonb) then 120 when p.version='report-v3' then public.kickx_observed_fixture_minutes(f.id) else 90 end)) or exists(select 1 from jsonb_array_elements(p_results) x join public.football_match_stats m on m.player_id=p_player and m.fixture_id=x->>'fixtureId' where x->>'status'='not-played' and (m.stats->>'minutes_played')::numeric is distinct from 0) then raise exception 'INVALID_INPUT';end if;
 if exists(select 1 from public.player_calculation_state where player_id=p_player and input_hash=p_hash and rule_version=p.version) and exists(select 1 from public.player_market_snapshots where id=p_player and pricing_status='ready') then return jsonb_build_object('unchanged',true);end if;
 if p.version='report-v3' and exists(select 1 from jsonb_array_elements(p_results) x join public.fixtures f on f.id=x->>'fixtureId' where x->>'status' in('ready','provisional','not-played') and public.kickx_regular_fixture(f.id) is distinct from true) then raise exception 'REGULAR_SEASON_SCOPE_REQUIRED';end if;
 -- A previously published score becoming incomplete must not erase asset value.
 if exists(select 1 from public.performance_results old where old.player_id=p_player and (p.version<>'report-v3' or old.rule_version=p.version and exists(select 1 from public.fixtures z where z.id=old.fixture_id and z.league_id in('bsd-1','bsd-3','bsd-4','bsd-5','bsd-6') and public.kickx_regular_fixture(z.id) is true)) and old.status in('ready','provisional') and not exists(select 1 from jsonb_array_elements(p_results) x where x->>'fixtureId'=old.fixture_id and x->>'status' in('ready','provisional','not-played'))) then
  update public.player_market_snapshots set pricing_status='pending' where id=p_player;
  insert into public.operation_audit(actor,action,target,detail) values(p_actor,'calculation.withheld',p_player,'{"reason":"PREVIOUS_RESULT_NOW_INCOMPLETE"}');
  return jsonb_build_object('withheld',true,'reason','PREVIOUS_RESULT_NOW_INCOMPLETE');
 end if;
 select coalesce(jsonb_agg(x||jsonb_build_object('startedAt',f.starts_at,'endedAt',public.kickx_fixture_valuation_at(f.id),'season',f.season,'minutes',m.stats->'minutes_played') order by f.starts_at,f.id),'[]') into enriched
 from jsonb_array_elements(p_results) x join public.football_match_stats m on m.player_id=p_player and m.fixture_id=x->>'fixtureId' join public.fixtures f on f.id=m.fixture_id;
 if p.version='report-v3' then
  plan:=public.kickx_report_plan((select coalesce(jsonb_agg(x),'[]') from jsonb_array_elements(enriched) x join public.fixtures f on f.id=x->>'fixtureId' where f.league_id in('bsd-1','bsd-3','bsd-4','bsd-5','bsd-6') and public.kickx_regular_fixture(f.id) is true),public.kickx_report_baseline(p_player,(select position from public.players where id=p_player),p.report_reference,p.report_parameters),p.report_parameters);
 else plan:=public.kickx_market_plan(enriched,p.pricing_reference_at,p.pricing_reference_season);end if;
 select price::bigint,pricing_status into old_value,old_pricing_status from public.player_market_snapshots where id=p_player;
 select pricing into old_plan from public.calculation_revisions where player_id=p_player and rule_version=p.version order by created_at desc,id desc limit 1;
 old_ready:=old_pricing_status='ready';
 -- Newly finished but unscorable matches cannot silently vanish from the last-five window.
 withheld:=case when p.version='report-v3' then exists(select 1 from jsonb_array_elements(p_results) x join public.fixtures f on f.id=x->>'fixtureId' where f.league_id in('bsd-1','bsd-3','bsd-4','bsd-5','bsd-6') and public.kickx_regular_fixture(f.id) is distinct from false and f.season>(p.report_reference->>'season')::integer and f.status='FT' and x->>'status'='blocked') else exists(select 1 from jsonb_array_elements(p_results) x join public.fixtures f on f.id=x->>'fixtureId' where f.status in('FT','AET','PEN') and f.starts_at>p.pricing_reference_at and x->>'status'='blocked' and (not p.club_competitions_enabled or f.league_id in ('bsd-1','bsd-3','bsd-4','bsd-5','bsd-6')))
 or (jsonb_array_length(plan->'steps')>0 and exists(select 1 from
  (select x from jsonb_array_elements(p_results) x join public.fixtures f on f.id=x->>'fixtureId'
   where f.status in('FT','AET','PEN') and (x->>'status'<>'blocked' or not p.club_competitions_enabled or f.league_id in ('bsd-1','bsd-3','bsd-4','bsd-5','bsd-6')) and x->>'status'<>'not-played' order by f.starts_at desc,f.id desc limit 5) candidates
  where x->>'status'='blocked')) end;
 value_now:=case when withheld then coalesce(old_value,p.initial_price) else (plan->>'price')::bigint end;
 delete from public.performance_results where player_id=p_player and fixture_id not in(select value->>'fixtureId' from jsonb_array_elements(enriched));
 update public.player_match_records set performance=null,rule_version=null where player_id=p_player
  and (performance is not null or rule_version is not null)
  and not exists(select 1 from jsonb_array_elements(enriched) x where x->>'fixtureId'=fixture_id and x->>'status' in('ready','provisional'));
 for r in select value from jsonb_array_elements(enriched) loop
  insert into public.performance_results(player_id,fixture_id,score,status,rule_version,input_hash,position,breakdown,warnings)
  values(p_player,r->>'fixtureId',(r->>'score')::numeric,r->>'status',p.version,p_hash,r->>'position',r->'breakdown',r->'warnings')
  on conflict(player_id,fixture_id) do update set score=excluded.score,status=excluded.status,rule_version=excluded.rule_version,
   input_hash=excluded.input_hash,position=excluded.position,breakdown=excluded.breakdown,warnings=excluded.warnings,
   calculated_at=clock_timestamp(),source_hash=null
  where (performance_results.score,performance_results.status,performance_results.rule_version,performance_results.position,performance_results.breakdown,performance_results.warnings)
   is distinct from (excluded.score,excluded.status,excluded.rule_version,excluded.position,excluded.breakdown,excluded.warnings);
  if r->>'status' in('ready','provisional') then latest:=(r->>'score')::numeric;update public.player_match_records set performance=latest,rule_version=p.version where player_id=p_player and fixture_id=r->>'fixtureId' and (performance,rule_version) is distinct from (latest,p.version);end if;
 end loop;
 if p.version='report-v3' then
 insert into public.player_initial_values(player_id,rule_version,detail,input_hash) values(p_player,p.version,plan->'baseline',p_hash)
 on conflict(player_id) do update set rule_version=excluded.rule_version,detail=excluded.detail,input_hash=excluded.input_hash,updated_at=clock_timestamp() where (player_initial_values.rule_version,player_initial_values.detail) is distinct from (excluded.rule_version,excluded.detail);
 end if;
 if withheld then
  update public.player_market_snapshots set pricing_status='pending' where id=p_player;
  insert into public.operation_audit(actor,action,target,detail) values(p_actor,'calculation.withheld',p_player,'{"reason":"LATEST_RESULT_INCOMPLETE"}');
  return jsonb_build_object('withheld',true,'reason','LATEST_RESULT_INCOMPLETE','price',value_now);
 end if;
 if p.version<>'report-v3' then
 insert into public.player_initial_values(player_id,rule_version,detail,input_hash) values(p_player,p.version,plan->'baseline',p_hash)
 on conflict(player_id) do update set rule_version=excluded.rule_version,detail=excluded.detail,input_hash=excluded.input_hash,updated_at=clock_timestamp() where (player_initial_values.rule_version,player_initial_values.detail) is distinct from (excluded.rule_version,excluded.detail);
 end if;
 delete from public.player_price_results where player_id=p_player and fixture_id not in(select value->>'fixtureId' from jsonb_array_elements(plan->'steps'));
 for r in select value from jsonb_array_elements(plan->'steps') loop
  insert into public.player_price_results(player_id,fixture_id,rule_version,played_at,price_before,price_after,target_price,form_score,change_percent,window_fixture_ids,input_hash)
  values(p_player,r->>'fixtureId',p.version,(r->>'playedAt')::timestamptz,(r->>'priceBefore')::bigint,(r->>'priceAfter')::bigint,(r->>'targetPrice')::bigint,(r->>'formScore')::numeric,(r->>'changePercent')::numeric,r->'window',(select input_hash from public.performance_results where player_id=p_player and fixture_id=r->>'fixtureId'))
  on conflict(player_id,fixture_id) do update set rule_version=excluded.rule_version,played_at=excluded.played_at,
   price_before=excluded.price_before,price_after=excluded.price_after,target_price=excluded.target_price,
   form_score=excluded.form_score,change_percent=excluded.change_percent,window_fixture_ids=excluded.window_fixture_ids,input_hash=excluded.input_hash
  where (player_price_results.rule_version,player_price_results.played_at,player_price_results.price_before,player_price_results.price_after,
   player_price_results.target_price,player_price_results.form_score,player_price_results.change_percent,player_price_results.window_fixture_ids,player_price_results.input_hash)
   is distinct from (excluded.rule_version,excluded.played_at,excluded.price_before,excluded.price_after,excluded.target_price,excluded.form_score,excluded.change_percent,excluded.window_fixture_ids,excluded.input_hash);
 end loop;
 insert into public.calculation_revisions(player_id,input_hash,rule_version,previous_price,new_price,results,pricing,actor) values(p_player,p_hash,p.version,old_value,value_now,p_results,plan,p_actor);
 insert into public.player_calculation_state(player_id,input_hash,rule_version) values(p_player,p_hash,p.version) on conflict(player_id) do update set input_hash=excluded.input_hash,rule_version=excluded.rule_version,calculated_at=clock_timestamp();
 price_changed:=old_value is distinct from value_now or (old_plan is null and not coalesce(old_ready,false));
 insert into public.player_market_snapshots(id,price,change_percent,performance,performance_rule_version,pricing_rule_version,volume,pricing_status)
 values(p_player,value_now,case when p.version='report-v3' then coalesce((plan#>>'{steps,-1,changePercent}')::numeric,0) when old_value>0 then round((value_now-old_value)*100.0/old_value,4) else null end,latest,case when latest is not null then p.version end,p.version,(select count(*) from public.trades where player_id=p_player),'ready')
 on conflict(id) do update set price=excluded.price,volume=excluded.volume,
 change_percent=case when price_changed then excluded.change_percent else public.player_market_snapshots.change_percent end,
 performance=excluded.performance,performance_rule_version=excluded.performance_rule_version,pricing_rule_version=excluded.pricing_rule_version,pricing_status='ready',
 updated_at=case when price_changed then clock_timestamp() else public.player_market_snapshots.updated_at end;
 -- One service-launch point plus each completed post-launch game, including verified DNPs.
 -- Replace this derived chart only after the previous state has been privately archived.
 if p.version='report-v3' and old_plan is distinct from plan then
  delete from public.price_history where player_id=p_player;
  insert into public.price_history(player_id,recorded_at,value,rule_version)
  values(p_player,to_timestamp(coalesce((p.report_parameters->>'valuationStartMs')::numeric,0)/1000),(plan#>>'{baseline,price}')::numeric,p.version);
  insert into public.price_history(player_id,recorded_at,value,rule_version)
  select p_player,(x->>'playedAt')::timestamptz,(x->>'priceAfter')::numeric,p.version from jsonb_array_elements(plan->'steps')x;
 end if;
 if price_changed then
  if p.version<>'report-v3' then insert into public.price_history(player_id,recorded_at,value,rule_version) values(p_player,clock_timestamp(),value_now,p.version);end if;
  insert into public.asset_snapshots(user_id,value) select user_id,public.kickx_assets(user_id) from public.holdings where player_id=p_player;
 end if;
 insert into public.operation_audit(actor,action,target,detail) values(p_actor,'calculation.publish',p_player,jsonb_build_object('price',value_now,'results',jsonb_array_length(p_results),'baseline',plan->'baseline','lastStep',plan->'steps'->-1,'correction',old_plan is not null));
 return jsonb_build_object('unchanged',false,'price',value_now,'performance',latest,'initialPrice',plan#>'{baseline,price}','pricing',plan);
end $$;

-- A non-appearance is neither an appearance nor a source of missing played-match totals.
create or replace function public.kickx_report_refresh_summaries() returns void language plpgsql set search_path='' as $$begin
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('kickx:bsd-import',0));
 with games as materialized(select id,season,league_id from public.fixtures where status='FT'and public.kickx_regular_fixture(id)is true),
 played as materialized(select ms.player_id,ms.normalized,f.season,f.league_id from public.football_match_stats ms join games f on f.id=ms.fixture_id where coalesce((ms.stats->>'minutes_played')::numeric,0)>0),
 latest as(select player_id,max(season)season from played group by player_id),
 removed as(delete from public.player_season_summaries ss where ss.stats_scope='imported_matches'and not exists(select 1 from played p where p.player_id=ss.id) returning ss.id)
 insert into public.player_season_summaries(id,season,goals,assists,minutes,league_ids,stats_scope,matches_imported)
 select ms.player_id,ms.season,
 case when count(ms.normalized#>>'{values,goals}')=count(*)then sum((ms.normalized#>>'{values,goals}')::integer)end,
 case when count(ms.normalized#>>'{values,assists}')=count(*)then sum((ms.normalized#>>'{values,assists}')::integer)end,
 case when count(ms.normalized#>>'{values,minutes}')=count(*)then sum((ms.normalized#>>'{values,minutes}')::integer)end,
 array_agg(distinct ms.league_id),'imported_matches',count(*)
 from played ms join latest l on l.player_id=ms.player_id and l.season is not distinct from ms.season group by ms.player_id,ms.season
 on conflict(id)do update set season=excluded.season,goals=excluded.goals,assists=excluded.assists,minutes=excluded.minutes,
 league_ids=excluded.league_ids,stats_scope=excluded.stats_scope,matches_imported=excluded.matches_imported,updated_at=clock_timestamp();
end $$;


-- Queue the approved reset in one statement rather than one function call per player.
create or replace function public.kickx_activate_report_policy() returns integer language plpgsql set search_path='' as $$
declare p public.kickx_policy%rowtype;k text;n integer:=0;begin
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('kickx:bsd-import',0));perform public.kickx_economy_lock();
 select * into strict p from public.kickx_policy;
 if p.version='report-v3' and p.valuation_rebuild->>'status'='active' then return 0;end if;
 if p.valuation_rebuild->>'status' is distinct from 'validated' then raise exception 'VALUATION_AUDIT_REQUIRED';end if;
 -- Decompress the frozen JSON once for the whole reset, rather than per player.
 p.report_reference:=p.report_reference||'{}'::jsonb;
 if not exists(select 1 from storage.objects o where o.bucket_id='kickx-calculation-archives' and o.name=p.valuation_rebuild#>>'{backup,path}') then raise exception 'VALUATION_BACKUP_REQUIRED';end if;
 if p.report_reference->>'status' is distinct from 'ready' or jsonb_array_length(p.report_reference->'archives')=0
 or (p.report_reference->>'completed')::integer<>(p.report_reference->>'fixtureCount')::integer then raise exception 'REFERENCE_NOT_READY';end if;
 foreach k in array array['GK','DF','MF','FW'] loop
  if coalesce(jsonb_array_length(p.report_reference->'groups'->k->'baselines'),0)=0 then raise exception 'REFERENCE_NOT_READY';end if;
 end loop;
 if exists(select 1 from jsonb_array_elements(p.report_reference->'archives') a where not exists(
  select 1 from storage.objects o where o.bucket_id='kickx-calculation-archives' and o.name=a->>'path')) then raise exception 'REFERENCE_ARCHIVE_MISSING';end if;
 if p.report_reference->>'regularSeasonScopeVerified' is distinct from 'true' then raise exception 'REGULAR_SEASON_SCOPE_REQUIRED';end if;
 update public.kickx_policy set version='report-v3',club_competitions_enabled=false,pricing_reference_at=timestamptz '2026-09-30T15:00:00Z',valuation_rebuild=valuation_rebuild||jsonb_build_object('status','active','activatedAt',clock_timestamp()),pricing_reference_season=(report_reference->>'season')::integer+1 where id=true;
 perform public.kickx_report_refresh_summaries();
 delete from public.realtime_fixture_tasks t using public.fixtures f where f.id=t.fixture_id and f.league_id not in('bsd-1','bsd-3','bsd-4','bsd-5','bsd-6');
 -- Reset derived market prices to the audited initial basis. Never alter trades, wallet balances or acquisition costs.
 with baseline as materialized(select z.id,public.kickx_report_baseline(z.id,z.position,p.report_reference,p.report_parameters)detail from public.players z where public.kickx_market_eligible(z.id))
 update public.player_market_snapshots s set price=(b.detail->>'price')::numeric,performance=null,change_percent=0,pricing_status='pending',performance_rule_version=null,pricing_rule_version='report-v3',updated_at=clock_timestamp()
 from baseline b where s.id=b.id and b.detail is not null;
 insert into public.calculation_queue(player_id)select id from public.players where public.kickx_market_eligible(id)
 on conflict(player_id)do update set revision=gen_random_uuid(),queued_at=now(),retry_at=now(),attempts=0,error_code=null;
 get diagnostics n=row_count;
 insert into public.operation_audit(action,detail) values('policy.report-v3',jsonb_build_object('referenceHash',p.report_reference->>'hash','parameters',p.report_parameters));
 return n;
end $$;

create or replace function public.kickx_observe_roster() returns trigger language plpgsql set search_path='' as $$
declare ids text[];last_row public.football_roster_observations%rowtype;begin
 if new.kind<>'squad' or jsonb_typeof(new.raw->'players') is distinct from 'array' then return new;end if;
 select array_agg('bsd-'||(x->>'id') order by (x->>'id')::bigint) into ids from jsonb_array_elements(new.raw->'players')x;
 if coalesce(array_length(ids,1),0)=0 then return new;end if;
 select * into last_row from public.football_roster_observations where team_id='bsd-'||new.external_id order by observed_at desc limit 1 for update;
 if found and last_row.player_ids=ids and new.updated_at<=last_row.verified_at+interval '7 days' then
  update public.football_roster_observations set verified_at=greatest(verified_at,new.updated_at) where team_id=last_row.team_id and observed_at=last_row.observed_at;
 else insert into public.football_roster_observations values('bsd-'||new.external_id,new.updated_at,new.updated_at,ids);end if;
 return new;
end $$;
drop trigger if exists kickx_roster_observed on public.football_entity_sources;
drop trigger if exists aa_roster_observed on public.football_entity_sources;
create trigger aa_roster_observed before insert or update on public.football_entity_sources for each row execute function public.kickx_observe_roster();

-- The completed catalog audit proves these exact unchanged squad snapshots were
-- checked before the backup existed. Its creation time is a conservative witness.
create or replace function public.kickx_attest_audited_rosters() returns integer language plpgsql set search_path='' as $$
declare at_time timestamptz;n integer;begin
 select o.created_at into at_time from public.kickx_policy p join storage.objects o on o.bucket_id='kickx-calculation-archives'and o.name=p.valuation_rebuild#>>'{backup,path}'
 where p.valuation_rebuild#>>'{audit,complete}'='true'and p.valuation_rebuild#>>'{audit,teams}'='96';
 if at_time is null then return 0;end if;
 insert into public.football_roster_observations(team_id,observed_at,verified_at,player_ids)
 select t.id,at_time,at_time,array_agg('bsd-'||(x->>'id')order by (x->>'id')::bigint)
 from public.football_entity_sources e join public.teams t on t.id='bsd-'||e.external_id cross join lateral jsonb_array_elements(e.raw->'players')x
 where e.kind='squad'and t.league_id in('bsd-1','bsd-3','bsd-4','bsd-5','bsd-6')and e.updated_at<=at_time group by t.id
 on conflict(team_id,observed_at)do nothing;get diagnostics n=row_count;
 if n>0 then
  update public.football_event_sources s set non_participation_seeded_at=null from public.fixtures f where f.id=s.fixture_id and f.starts_at between at_time and at_time+interval '7 days'and f.status='FT'and public.kickx_regular_fixture(f.id)is true;
  insert into public.operation_audit(action,detail)values('roster.audit-attested',jsonb_build_object('teams',n,'witnessedAt',at_time));
 end if;return n;
end $$;
revoke all on function public.kickx_attest_audited_rosters()from public,anon,authenticated;
grant execute on function public.kickx_attest_audited_rosters()to service_role;

create or replace function public.kickx_replace_regular_reference(p_expected_hash text,p_reference jsonb) returns jsonb language plpgsql set search_path='' as $$
declare p public.kickx_policy%rowtype;n integer;before_hash jsonb;eligible text[];begin
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('kickx:bsd-import',0));perform public.kickx_economy_lock();
 select * into strict p from public.kickx_policy;
 if p.report_reference->>'hash'=p_reference->>'hash' and p.report_reference->>'regularSeasonScopeVerified'='true' then return jsonb_build_object('unchanged',true);end if;
 if p.report_reference->>'hash' is distinct from p_expected_hash then raise exception 'REFERENCE_CHANGED';end if;
 if p_reference->>'regularSeasonScopeVerified' is distinct from 'true' or p_reference->>'status' is distinct from 'ready' or coalesce(length(p_reference->>'hash'),0)<>64
 or coalesce((p_reference->>'completed')::integer,0)<>jsonb_array_length(p_reference->'archives')
 or (p_reference->>'completed')::integer<>(p_reference->>'fixtureCount')::integer or (p_reference->>'fixtureCount')::integer<1500
 or not exists(select 1 from storage.objects where bucket_id='kickx-calculation-archives' and name=p_reference#>>'{scopeAudit,previousReferenceBackup,path}') then raise exception 'REGULAR_SEASON_SCOPE_REQUIRED';end if;
 before_hash:=public.kickx_valuation_integrity();
 perform public.kickx_attest_audited_rosters();
 select array_agg(id)into eligible from public.players where public.kickx_market_eligible(id);
 update public.kickx_policy set report_reference=p_reference,valuation_rebuild=(valuation_rebuild-'portfolioRebuiltAt'-'assetSnapshotsRebuilt')||jsonb_build_object('status','validated','scopeCorrectedAt',clock_timestamp())where id=true;
 n:=public.kickx_activate_report_policy();
 insert into public.player_initial_values(player_id,rule_version,detail,input_hash)
 select z.id,'report-v3',b.detail,p_reference->>'hash' from public.players z cross join lateral(select public.kickx_report_baseline(z.id,z.position,p_reference,p.report_parameters)detail)b where z.id=any(eligible) and b.detail is not null
 on conflict(player_id)do update set rule_version=excluded.rule_version,detail=excluded.detail,input_hash=excluded.input_hash,updated_at=clock_timestamp();
 delete from public.price_history where player_id=any(eligible);
 delete from public.player_price_results where player_id=any(eligible);
 insert into public.price_history(player_id,recorded_at,value,rule_version)
 select s.id,timestamptz '2026-09-30T15:00:00Z',s.price,'report-v3' from public.player_market_snapshots s where s.id=any(eligible);
 if before_hash is distinct from public.kickx_valuation_integrity()then raise exception 'VALUATION_FINANCIAL_INTEGRITY';end if;
 insert into public.operation_audit(action,detail)values('valuation.regular-scope',jsonb_build_object('fromHash',p_expected_hash,'hash',p_reference->>'hash','excluded',p_reference#>'{scopeAudit,excluded}','queued',n));
 return jsonb_build_object('queued',n,'hash',p_reference->>'hash');
end $$;
revoke all on function public.kickx_replace_regular_reference(text,jsonb) from public,anon,authenticated;
grant execute on function public.kickx_replace_regular_reference(text,jsonb) to service_role;

create or replace function public.kickx_calculation_input(p_player text,p_full boolean default false) returns jsonb language plpgsql stable set search_path='' as $$
declare policy jsonb;records jsonb;total integer;begin
 select jsonb_build_object('version',version,'club_competitions_enabled',club_competitions_enabled,
  'pricing_reference_at',pricing_reference_at,'pricing_reference_season',pricing_reference_season,'report_parameters',report_parameters,'reportBaseline',case when version='report-v3' then public.kickx_report_baseline(p_player,(select position from public.players where id=p_player),report_reference,report_parameters) end) into policy from public.kickx_policy;
 select count(*) into total from public.football_match_stats where player_id=p_player;
 if total>10000 then raise exception 'CALCULATION_SCOPE_TOO_LARGE';end if;
 select coalesce(jsonb_agg(jsonb_build_object('player_id',m.player_id,'fixture_id',m.fixture_id,'team_id',m.team_id,
  'stats',m.stats,'legacy_stats',m.legacy_stats,'updated_at',m.updated_at,
  'fixtures',jsonb_build_object('id',f.id,'starts_at',f.starts_at,'season',f.season,'status',f.status,
   'league_id',f.league_id,'durationMinutes',case when policy->>'version'='report-v3' then public.kickx_observed_fixture_minutes(f.id) else 90 end,'home_team_id',f.home_team_id,'away_team_id',f.away_team_id,'home_score',f.home_score,'away_score',f.away_score,'updated_at',f.updated_at,
   'football_event_sources',jsonb_build_object('detail',coalesce(s.detail,'{}'::jsonb)||jsonb_build_object('stage',coalesce(f.stage,s.detail->>'stage'),'round_label',coalesce(f.round_label,s.detail->>'round_label')),'lineups',s.lineups,'incidents',s.incidents,'updated_at',s.updated_at)))
  order by f.starts_at,f.id),'[]') into records
 from public.kickx_calculation_sources(p_player) c join public.football_match_stats m on m.player_id=p_player and m.fixture_id=c.fixture_id
 join public.fixtures f on f.id=m.fixture_id left join public.football_event_sources s on s.fixture_id=f.id
 where p_full or not c.cached or policy->>'version' not in('form-v2','report-v3');
 return jsonb_build_object('policy',policy,'token',public.kickx_calculation_token(p_player),'records',records,'total',total,'reused',total-jsonb_array_length(records));
end $$;

create or replace function public.kickx_publish_calculation_delta(p_actor uuid,p_player text,p_token text,p_results jsonb)
returns jsonb language plpgsql set search_path='' as $$
declare p public.kickx_policy%rowtype;expected jsonb;combined jsonb;answer jsonb;hash text;needed jsonb;supplied jsonb;begin
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('kickx:bsd-import',0));
 perform public.kickx_economy_lock();
 select * into strict p from public.kickx_policy;
 if p.version not in('form-v2','report-v3') or jsonb_typeof(p_results) is distinct from 'array' then raise exception 'INVALID_INPUT';end if;
 if p.version='report-v3' and exists(select 1 from jsonb_array_elements(p_results)x where x->>'scoringRevision' is distinct from 'regular-season-20261030')then raise exception 'SCORING_REVISION_REQUIRED';end if;
 if p_token is distinct from public.kickx_calculation_token(p_player) then raise exception 'SOURCE_CHANGED';end if;
 select coalesce(jsonb_agg(fixture_id order by fixture_id),'[]') into needed from public.kickx_calculation_sources(p_player) where not cached;
 select coalesce(jsonb_agg(value->>'fixtureId' order by value->>'fixtureId'),'[]') into supplied from jsonb_array_elements(p_results);
 -- A concurrent calculation may already have cached the same source. Allow its
 -- identical result to be resubmitted, but never an omitted or foreign fixture.
 if exists(select 1 from jsonb_array_elements_text(needed) n where not exists(select 1 from jsonb_array_elements(p_results) x where x->>'fixtureId'=n))
 or exists(select 1 from jsonb_array_elements(p_results) x where not exists(select 1 from public.football_match_stats m where m.player_id=p_player and m.fixture_id=x->>'fixtureId'))
 or jsonb_array_length(supplied)<>(select count(distinct value->>'fixtureId') from jsonb_array_elements(p_results)) then raise exception 'INVALID_DELTA';end if;
 select coalesce(jsonb_agg(coalesce(x.value-'minutes',jsonb_build_object('fixtureId',m.fixture_id,'position',r.position,'score',r.score,
  'status',r.status,'breakdown',r.breakdown,'warnings',r.warnings,'ruleVersion',r.rule_version)||
  case when p.version='report-v3' then '{"scoringRevision":"regular-season-20261030"}'::jsonb when p.club_competitions_enabled then '{"scoringRevision":"club-competitions-v1"}'::jsonb else '{}'::jsonb end) order by f.starts_at,f.id),'[]') into combined
 from public.football_match_stats m join public.fixtures f on f.id=m.fixture_id
 left join public.performance_results r on r.player_id=m.player_id and r.fixture_id=m.fixture_id
 left join jsonb_array_elements(p_results) x on x.value->>'fixtureId'=m.fixture_id where m.player_id=p_player;
 select coalesce(jsonb_agg(jsonb_build_object('fixture',m.fixture_id,'statsAt',m.updated_at,'sourceAt',s.updated_at,'fixtureAt',f.updated_at) order by m.fixture_id),'[]') into expected
 from public.football_match_stats m join public.fixtures f on f.id=m.fixture_id left join public.football_event_sources s on s.fixture_id=f.id where m.player_id=p_player;
 -- Equal scores can still produce different prices after minutes/date/season corrections.
 -- Hash semantic pricing inputs as well as the score evidence, not poll timestamps.
 select md5(jsonb_build_array(p.version,p.pricing_reference_at,p.pricing_reference_season,p.club_competitions_enabled,
  case when p.version='report-v3' then p.report_parameters end,case when p.version='report-v3' then p.report_reference->>'hash' end,
  coalesce(jsonb_agg(x||jsonb_build_object('startedAt',f.starts_at,'season',f.season,'minutes',m.stats->'minutes_played') order by f.starts_at,f.id),'[]'))::text)
 into hash from jsonb_array_elements(combined) x join public.football_match_stats m on m.player_id=p_player and m.fixture_id=x->>'fixtureId'
 join public.fixtures f on f.id=m.fixture_id;
 answer:=public.kickx_publish_calculation(p_actor,p_player,hash,expected,combined);
 -- Incomplete corrections can be withheld before publication. Mark only evidence
 -- whose persisted score actually matches the newly computed result as reusable.
 update public.performance_results r set source_hash=c.source_hash
 from public.kickx_calculation_sources(p_player) c,jsonb_array_elements(p_results) x
 where r.player_id=p_player and r.fixture_id=c.fixture_id and r.fixture_id=x->>'fixtureId'
  and (r.score,r.status,r.rule_version,r.position,r.breakdown,r.warnings)
   is not distinct from ((x->>'score')::numeric,x->>'status',x->>'ruleVersion',x->>'position',x->'breakdown',x->'warnings')
  and r.source_hash is distinct from c.source_hash;
 return answer-'pricing';
end $$;

create or replace function public.kickx_seed_non_participation() returns integer language plpgsql set search_path='' set jit=off as $$
declare inserted integer;affected text[];game_ids text[];begin
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('kickx:bsd-import',0));
 select array_agg(id) into game_ids from(select f.id from public.fixtures f join public.football_event_sources s on s.fixture_id=f.id
 where f.league_id in('bsd-1','bsd-3','bsd-4','bsd-5','bsd-6') and f.status='FT' and public.kickx_regular_fixture(f.id)is true
 and f.starts_at>=timestamptz '2026-09-30T15:00:00Z'-interval '4 hours'
 and case when f.starts_at>=timestamptz '2026-09-30T15:00:00Z' then true else public.kickx_fixture_valuation_at(f.id)>=timestamptz '2026-09-30T15:00:00Z' end
 and s.lineups->>'lineup_status'='confirmed' and jsonb_typeof(s.incidents->'incidents')='array'
 and (s.non_participation_seeded_at is null or s.non_participation_seeded_at<s.updated_at) order by s.updated_at,f.id limit 8) q;
 if game_ids is null then return 0;end if;
 with games as(
 select f.*,s.lineups,s.incidents from public.fixtures f join public.football_event_sources s on s.fixture_id=f.id
 where f.id=any(game_ids)
 ), sides as(
 select g.*,v.value side,v.key side_key,'bsd-'||(v.value->>'team_id') team_id
 from games g cross join lateral jsonb_each(g.lineups->'lineups')v
 ), members as(
 select s.id fixture_id,s.team_id,'bsd-'||(x->>'id') player_id,'confirmed-lineup' kind from sides s cross join lateral jsonb_array_elements(coalesce(s.side->'substitutes','[]'))x
 union
 select s.id,s.team_id,'bsd-'||(x->>'id'),'unavailable-list' from sides s cross join lateral jsonb_array_elements(coalesce(s.lineups->'unavailable_players'->s.side_key,'[]'))x
 union
 select s.id,s.team_id,x,'observed-squad' from sides s
 cross join lateral(select * from public.football_roster_observations o where o.team_id=s.team_id and o.observed_at<=s.starts_at
 and o.verified_at>=s.starts_at-interval '7 days' order by o.observed_at desc limit 1)o cross join lateral unnest(o.player_ids)x
 ), candidates as(
 select distinct on(m.player_id,m.fixture_id)m.* from members m join games g on g.id=m.fixture_id join public.players p on p.id=m.player_id
 where not exists(select 1 from jsonb_each(g.lineups->'lineups')side cross join lateral jsonb_array_elements(side.value->'players')x where 'bsd-'||(x->>'id')=m.player_id)
 and not exists(select 1 from jsonb_array_elements(g.incidents->'incidents')e where (e->>'type'='substitution' and 'bsd-'||(e->>'player_in_id')=m.player_id)or(e->>'type'='goal' and 'bsd-'||(e->>'player_id')=m.player_id))
 order by m.player_id,m.fixture_id,m.kind
 ), written as(
 insert into public.football_match_stats(player_id,fixture_id,team_id,stats,normalized)
 select player_id,fixture_id,team_id,jsonb_build_object('minutes_played',0,'_roster_evidence',jsonb_build_object('fixtureId',fixture_id,'teamId',team_id,'playerId',player_id,'kind',kind)),
 '{"version":"membership-v1","quality":{"minutes":"verified_non_participation"}}'::jsonb from candidates
 on conflict(player_id,fixture_id)do nothing returning player_id,fixture_id,team_id
 ), records as(
 insert into public.player_match_records(player_id,fixture_id,played_at,opponent,minutes)
 select w.player_id,w.fixture_id,f.starts_at,coalesce(t.name_ko,t.name),0 from written w join public.fixtures f on f.id=w.fixture_id join public.teams t on t.id=case when f.home_team_id=w.team_id then f.away_team_id else f.home_team_id end
 on conflict(player_id,fixture_id)do nothing returning player_id
 )
 select count(*),array_agg(distinct player_id) into inserted,affected from written;
 perform public.kickx_queue_player(x) from unnest(affected)x;
 update public.football_event_sources set non_participation_seeded_at=updated_at where fixture_id=any(game_ids);
 return inserted;
end $$;

create or replace function public.kickx_non_participation_work() returns jsonb language plpgsql set search_path='' set jit=off as $$
declare n integer;remaining integer;begin
 n:=public.kickx_seed_non_participation();
 select count(*) into remaining from public.fixtures f join public.football_event_sources s on s.fixture_id=f.id where f.league_id in('bsd-1','bsd-3','bsd-4','bsd-5','bsd-6') and f.status='FT' and public.kickx_regular_fixture(f.id)is true
 and f.starts_at>=timestamptz '2026-09-30T15:00:00Z'-interval '4 hours'
 and case when f.starts_at>=timestamptz '2026-09-30T15:00:00Z' then true else public.kickx_fixture_valuation_at(f.id)>=timestamptz '2026-09-30T15:00:00Z' end
 and s.lineups->>'lineup_status'='confirmed' and jsonb_typeof(s.incidents->'incidents')='array'
 and (s.non_participation_seeded_at is null or s.non_participation_seeded_at<s.updated_at);
 return jsonb_build_object('inserted',n,'remaining',remaining);
end $$;
revoke all on function public.kickx_non_participation_work() from public,anon,authenticated;
grant execute on function public.kickx_non_participation_work() to service_role;

-- Keep verified derived non-appearances on replay and count actual regular-league appearances in totals.
do $migration$
declare d text;begin
 d:=pg_get_functiondef('public.apply_bsd_batch(jsonb)'::regprocedure);
 if strpos(d,'report-summary-appearances-20261030')>0 then return;end if;
 if strpos(d,'and ms.player_id=any(affected) and f.provider=')=0 or strpos(d,'and ms2.player_id=ms.player_id and f2.status')=0 then raise exception 'SUMMARY_IMPORT_PREDICATE_CHANGED';end if;
 d:=replace(d,'and ms.player_id=any(affected) and f.provider=', $new$and /* report-summary-appearances-20261030 */ (not exists(select 1 from public.kickx_policy where version='report-v3')or(coalesce((ms.stats->>'minutes_played')::numeric,0)>0 and public.kickx_regular_fixture(f.id)is true)) and ms.player_id=any(affected) and f.provider=$new$);
 d:=replace(d,'and ms2.player_id=ms.player_id and f2.status', $new$and (not exists(select 1 from public.kickx_policy where version='report-v3')or(coalesce((ms2.stats->>'minutes_played')::numeric,0)>0 and public.kickx_regular_fixture(f2.id)is true)) and ms2.player_id=ms.player_id and f2.status$new$);
 d:=replace(d,'delete from public.player_match_records r where r.fixture_id in',$new$delete from public.player_match_records r where not exists(select 1 from public.football_match_stats proof where proof.player_id=r.player_id and proof.fixture_id=r.fixture_id and proof.stats?'_roster_evidence') and r.fixture_id in$new$);
 d:=replace(d,'delete from public.football_match_stats r where r.fixture_id in',$new$delete from public.football_match_stats r where not(r.stats?'_roster_evidence') and r.fixture_id in$new$);
 execute d;
end $migration$;


-- Processing checkpoints do not change scoring evidence and must not queue every match participant.
do $migration$
declare d text;begin
 d:=pg_get_functiondef('public.kickx_queue_match_change()'::regprocedure);
 if strpos(d,$find$-'non_participation_seeded_at'$find$)>0 then return;end if;
 if strpos(d,$find$to_jsonb(new)-'updated_at'$find$)=0 then raise exception 'QUEUE_TRIGGER_DEFINITION_CHANGED';end if;
 d:=replace(d,$old$to_jsonb(new)-'updated_at'$old$,$new$to_jsonb(new)-'updated_at'-'non_participation_seeded_at'$new$);
 d:=replace(d,$old$to_jsonb(old)-'updated_at'$old$,$new$to_jsonb(old)-'updated_at'-'non_participation_seeded_at'$new$);
 execute d;
end $migration$;

