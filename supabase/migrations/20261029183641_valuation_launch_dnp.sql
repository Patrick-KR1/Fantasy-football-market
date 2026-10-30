-- Private launch/rebuild state; the existing public policy column grants remain unchanged.
alter table public.kickx_policy add column valuation_rebuild jsonb not null default '{"status":"requested","startsAt":"2026-09-30T15:00:00Z"}';
update public.kickx_policy set report_parameters=report_parameters||jsonb_build_object('nonParticipationRate',0.015,'valuationStartMs',extract(epoch from timestamptz '2026-09-30T15:00:00Z')*1000) where id=true;

-- Compact membership evidence: retain a new row only when a club roster changes.
create table public.football_roster_observations(
 team_id text not null references public.teams(id), observed_at timestamptz not null,
 verified_at timestamptz not null, player_ids text[] not null,
 primary key(team_id,observed_at),check(verified_at>=observed_at)
);
alter table public.football_roster_observations enable row level security;
revoke all on public.football_roster_observations from public,anon,authenticated;
grant select,insert,update,delete on public.football_roster_observations to service_role;
create function public.kickx_observe_roster() returns trigger language plpgsql set search_path='' as $$
declare ids text[];last_row public.football_roster_observations%rowtype;begin
 if new.kind<>'squad' or jsonb_typeof(new.raw->'players') is distinct from 'array' then return new;end if;
 select array_agg('bsd-'||(x->>'id') order by (x->>'id')::bigint) into ids from jsonb_array_elements(new.raw->'players')x;
 if coalesce(array_length(ids,1),0)=0 then return new;end if;
 select * into last_row from public.football_roster_observations where team_id='bsd-'||new.external_id order by observed_at desc limit 1 for update;
 if found and last_row.player_ids=ids then
  update public.football_roster_observations set verified_at=greatest(verified_at,new.updated_at) where team_id=last_row.team_id and observed_at=last_row.observed_at;
 else insert into public.football_roster_observations values('bsd-'||new.external_id,new.updated_at,new.updated_at,ids);end if;
 return new;
end $$;
revoke all on function public.kickx_observe_roster() from public,anon,authenticated;
create trigger kickx_roster_observed after insert or update on public.football_entity_sources for each row execute function public.kickx_observe_roster();
insert into public.football_roster_observations(team_id,observed_at,verified_at,player_ids)
select 'bsd-'||e.external_id,e.updated_at,e.updated_at,array_agg('bsd-'||(x->>'id') order by (x->>'id')::bigint)
from public.football_entity_sources e cross join lateral jsonb_array_elements(e.raw->'players')x where kind='squad' group by e.external_id,e.updated_at;

-- Historical "first fetched" timestamps are not actual final-whistle timestamps.
-- Use a near-live finish observation, otherwise an explicitly estimated end from match duration.
create function public.kickx_fixture_valuation_at(p_fixture text) returns timestamptz language sql stable set search_path='' as $$
 select case when finished_observed_at between starts_at+interval '60 minutes' and starts_at+interval '4 hours'
  then finished_observed_at else starts_at+(public.kickx_observed_fixture_minutes(id)+15)*interval '1 minute' end
 from public.fixtures where id=p_fixture
$$;
revoke all on function public.kickx_fixture_valuation_at(text) from public,anon,authenticated;
grant execute on function public.kickx_fixture_valuation_at(text) to service_role;

-- Only positive membership evidence can create a non-participation record.
-- Never backdate a current roster or replace a provider's unknown/positive minutes with zero.
create function public.kickx_seed_non_participation() returns integer language plpgsql set search_path='' as $$
declare inserted integer;affected text[];begin
 with games as(
 select f.*,s.lineups,s.incidents from public.fixtures f join public.football_event_sources s on s.fixture_id=f.id
 where f.league_id in('bsd-1','bsd-3','bsd-4','bsd-5','bsd-6') and f.status='FT'
 and public.kickx_fixture_valuation_at(f.id)>=timestamptz '2026-09-30T15:00:00Z'
 and s.lineups->>'lineup_status'='confirmed' and jsonb_typeof(s.incidents->'incidents')='array'
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
 return inserted;
end $$;
revoke all on function public.kickx_seed_non_participation() from public,anon,authenticated;
grant execute on function public.kickx_seed_non_participation() to service_role;

create or replace function public.kickx_report_plan(p_results jsonb,p_baseline jsonb,p_parameters jsonb)
returns jsonb language plpgsql immutable set search_path='' as $$
declare r jsonb;steps jsonb:='[]';window_ids jsonb:='[]';v bigint;before_v bigint;b numeric;c numeric;d numeric;q numeric;total numeric:=0;
 n integer:=0;season integer;next_season integer;t double precision;lo bigint;hi bigint;dnp boolean;at_time timestamptz;
 rate numeric:=coalesce((p_parameters->>'nonParticipationRate')::numeric,.015);begin
 if jsonb_typeof(p_results) is distinct from 'array' or p_baseline is null then raise exception 'INVALID_REPORT_BASELINE';end if;
 if rate<0 or rate>=1 then raise exception 'INVALID_REPORT_PARAMETERS';end if;
 b:=(p_baseline->>'seedScore')::numeric;v:=(p_baseline->>'price')::bigint;
 if (select count(*) from jsonb_array_elements(p_results))<>(select count(distinct x->>'fixtureId')from jsonb_array_elements(p_results)x) then raise exception 'INVALID_PRICING_MATCH';end if;
 for r in select value from jsonb_array_elements(p_results)
 where ((value->>'status' in('ready','provisional') and jsonb_typeof(value->'score')='number' and (value->>'minutes')::numeric>0 and (value->>'minutes')::numeric<=180)
 or (value->>'status'='not-played' and (value->>'minutes')::numeric=0))
 and (value->>'season')::integer>(p_baseline->>'season')::integer
 order by coalesce(value->>'endedAt',value->>'startedAt')::timestamptz,value->>'fixtureId' loop
  next_season:=(r->>'season')::integer;
  if season is distinct from next_season then season:=next_season;total:=0;n:=0;window_ids:='[]';end if;
  dnp:=r->>'status'='not-played';q:=null;
  if not dnp then
   q:=greatest((p_baseline->>'lower')::numeric,least((p_baseline->>'upper')::numeric,(r->>'score')::numeric));
   total:=total+q;n:=n+1;window_ids:=window_ids||jsonb_build_array(r->>'fixtureId');
  end if;
  c:=((p_parameters->>'kappa')::numeric*b+total)/((p_parameters->>'kappa')::numeric+n);
  d:=(c-b)/greatest(abs(b),(p_parameters->>'s')::numeric);
  at_time:=coalesce(r->>'endedAt',r->>'startedAt')::timestamptz;
  if extract(epoch from at_time)*1000<coalesce((p_parameters->>'valuationStartMs')::numeric,0) then continue;end if;
  if dnp then t:=v*(1-rate);else
   t:=(p_baseline->>'price')::double precision*exp((p_parameters->>'beta')::double precision*greatest(-(p_parameters->>'deviationLimit')::numeric,least((p_parameters->>'deviationLimit')::numeric,d))::double precision);
  end if;
  t:=greatest((p_parameters->>'minPrice')::double precision,least((p_parameters->>'maxPrice')::double precision,t));
  before_v:=v;lo:=greatest((p_parameters->>'minPrice')::bigint,ceil(before_v*(1-(p_parameters->>'maxDown')::numeric))::bigint);
  hi:=least((p_parameters->>'maxPrice')::bigint,floor(before_v*(1+(p_parameters->>'maxUp')::numeric))::bigint);
  v:=greatest(lo,least(hi,floor(t+0.5)::bigint));
  steps:=steps||jsonb_build_array(jsonb_build_object('fixtureId',r->>'fixtureId','playedAt',at_time,'priceBefore',before_v,'priceAfter',v,
   'targetPrice',floor(t+0.5)::bigint,'formScore',floor(c*1000000+0.5)/1000000,'changePercent',floor((v-before_v)*100.0/before_v*10000+0.5)/10000,
   'window',window_ids,'evidence',jsonb_build_object('season',season,'n',n,'reason',case when dnp then 'NON_PARTICIPATION' else 'PERFORMANCE'end,
    'nonParticipationRate',case when dnp then rate end,'rawScore',r->'score','boundedScore',q,'cumulativeSum',total,'cumulativeScore',c,'deviation',d,'target',t,'referenceHash',p_baseline->>'referenceHash')));
 end loop;
 return jsonb_build_object('version','report-v3','baseline',p_baseline,'price',v,'steps',steps);
end $$;
revoke all on function public.kickx_report_plan(jsonb,jsonb,jsonb) from public,anon,authenticated;
grant execute on function public.kickx_report_plan(jsonb,jsonb,jsonb) to service_role;


create or replace function public.kickx_activate_report_policy() returns integer language plpgsql set search_path='' as $$
declare p public.kickx_policy%rowtype;k text;r record;n integer:=0;begin
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('kickx:bsd-import',0));perform public.kickx_economy_lock();
 select * into strict p from public.kickx_policy;
 if p.version='report-v3' and p.valuation_rebuild->>'status'='active' then return 0;end if;
 if p.valuation_rebuild->>'status' is distinct from 'validated' then raise exception 'VALUATION_AUDIT_REQUIRED';end if;
 if not exists(select 1 from storage.objects o where o.bucket_id='kickx-calculation-archives' and o.name=p.valuation_rebuild#>>'{backup,path}') then raise exception 'VALUATION_BACKUP_REQUIRED';end if;
 if p.report_reference->>'status' is distinct from 'ready' or jsonb_array_length(p.report_reference->'archives')=0
 or (p.report_reference->>'completed')::integer<>(p.report_reference->>'fixtureCount')::integer then raise exception 'REFERENCE_NOT_READY';end if;
 foreach k in array array['GK','DF','MF','FW'] loop
  if coalesce(jsonb_array_length(p.report_reference->'groups'->k->'baselines'),0)=0 then raise exception 'REFERENCE_NOT_READY';end if;
 end loop;
 if exists(select 1 from jsonb_array_elements(p.report_reference->'archives') a where not exists(
  select 1 from storage.objects o where o.bucket_id='kickx-calculation-archives' and o.name=a->>'path')) then raise exception 'REFERENCE_ARCHIVE_MISSING';end if;
 update public.kickx_policy set version='report-v3',club_competitions_enabled=false,pricing_reference_at=timestamptz '2026-09-30T15:00:00Z',valuation_rebuild=valuation_rebuild||jsonb_build_object('status','active','activatedAt',clock_timestamp()),pricing_reference_season=(report_reference->>'season')::integer+1 where id=true;
 perform public.kickx_report_refresh_summaries();
 delete from public.realtime_fixture_tasks t using public.fixtures f where f.id=t.fixture_id and f.league_id not in('bsd-1','bsd-3','bsd-4','bsd-5','bsd-6');
 -- Reset derived market prices to the audited initial basis. Never alter trades, wallet balances or acquisition costs.
 update public.player_market_snapshots s set price=(b.detail->>'price')::numeric,performance=null,change_percent=0,pricing_status='pending',performance_rule_version=null,pricing_rule_version='report-v3',updated_at=clock_timestamp()
 from (select z.id,public.kickx_report_baseline(z.id,z.position,p.report_reference,p.report_parameters) detail from public.players z where public.kickx_market_eligible(z.id)) b where s.id=b.id and b.detail is not null;
 for r in select id from public.players where public.kickx_market_eligible(id) loop perform public.kickx_queue_player(r.id);n:=n+1;end loop;
 insert into public.operation_audit(action,detail) values('policy.report-v3',jsonb_build_object('referenceHash',p.report_reference->>'hash','parameters',p.report_parameters));
 return n;
end $$;

create or replace function public.kickx_calculation_token(p_player text) returns text language sql stable set search_path='' as $$
 select md5(jsonb_build_array(p.version,p.pricing_reference_at,p.pricing_reference_season,p.club_competitions_enabled,p.report_parameters,'launch-dnp-20261030',case when p.version='report-v3' then p.report_reference->>'hash' end,
  (select coalesce(jsonb_agg(jsonb_build_array(fixture_id,source_hash) order by fixture_id),'[]') from public.kickx_calculation_sources(p_player)))::text)
 from public.kickx_policy p
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
 -- A previously published score becoming incomplete must not erase asset value.
 if exists(select 1 from public.performance_results old where old.player_id=p_player and (p.version<>'report-v3' or old.rule_version=p.version and exists(select 1 from public.fixtures z where z.id=old.fixture_id and z.league_id in('bsd-1','bsd-3','bsd-4','bsd-5','bsd-6'))) and old.status in('ready','provisional') and not exists(select 1 from jsonb_array_elements(p_results) x where x->>'fixtureId'=old.fixture_id and x->>'status' in('ready','provisional','not-played'))) then
  update public.player_market_snapshots set pricing_status='pending' where id=p_player;
  insert into public.operation_audit(actor,action,target,detail) values(p_actor,'calculation.withheld',p_player,'{"reason":"PREVIOUS_RESULT_NOW_INCOMPLETE"}');
  return jsonb_build_object('withheld',true,'reason','PREVIOUS_RESULT_NOW_INCOMPLETE');
 end if;
 select coalesce(jsonb_agg(x||jsonb_build_object('startedAt',f.starts_at,'endedAt',public.kickx_fixture_valuation_at(f.id),'season',f.season,'minutes',m.stats->'minutes_played') order by f.starts_at,f.id),'[]') into enriched
 from jsonb_array_elements(p_results) x join public.football_match_stats m on m.player_id=p_player and m.fixture_id=x->>'fixtureId' join public.fixtures f on f.id=m.fixture_id;
 if p.version='report-v3' then
  plan:=public.kickx_report_plan((select coalesce(jsonb_agg(x),'[]') from jsonb_array_elements(enriched) x join public.fixtures f on f.id=x->>'fixtureId' where f.league_id in('bsd-1','bsd-3','bsd-4','bsd-5','bsd-6')),public.kickx_report_baseline(p_player,(select position from public.players where id=p_player),p.report_reference,p.report_parameters),p.report_parameters);
 else plan:=public.kickx_market_plan(enriched,p.pricing_reference_at,p.pricing_reference_season);end if;
 select price::bigint,pricing_status into old_value,old_pricing_status from public.player_market_snapshots where id=p_player;
 select pricing into old_plan from public.calculation_revisions where player_id=p_player and rule_version=p.version order by created_at desc,id desc limit 1;
 old_ready:=old_pricing_status='ready';
 -- Newly finished but unscorable matches cannot silently vanish from the last-five window.
 withheld:=case when p.version='report-v3' then exists(select 1 from jsonb_array_elements(p_results) x join public.fixtures f on f.id=x->>'fixtureId' where f.league_id in('bsd-1','bsd-3','bsd-4','bsd-5','bsd-6') and f.season>(p.report_reference->>'season')::integer and f.status='FT' and x->>'status'='blocked') else exists(select 1 from jsonb_array_elements(p_results) x join public.fixtures f on f.id=x->>'fixtureId' where f.status in('FT','AET','PEN') and f.starts_at>p.pricing_reference_at and x->>'status'='blocked' and (not p.club_competitions_enabled or f.league_id in ('bsd-1','bsd-3','bsd-4','bsd-5','bsd-6')))
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
 if withheld then
  update public.player_market_snapshots set pricing_status='pending' where id=p_player;
  insert into public.operation_audit(actor,action,target,detail) values(p_actor,'calculation.withheld',p_player,'{"reason":"LATEST_RESULT_INCOMPLETE"}');
  return jsonb_build_object('withheld',true,'reason','LATEST_RESULT_INCOMPLETE','price',value_now);
 end if;
 insert into public.player_initial_values(player_id,rule_version,detail,input_hash) values(p_player,p.version,plan->'baseline',p_hash)
 on conflict(player_id) do update set rule_version=excluded.rule_version,detail=excluded.detail,input_hash=excluded.input_hash,updated_at=clock_timestamp() where (player_initial_values.rule_version,player_initial_values.detail) is distinct from (excluded.rule_version,excluded.detail);
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

create function public.kickx_stage_valuation_rebuild(p_manifest jsonb) returns jsonb language plpgsql set search_path='' as $$
declare v jsonb;begin
 perform public.kickx_economy_lock();
 select valuation_rebuild into v from public.kickx_policy;
 if v->>'status' in('validated','active') then return v;end if;
 if p_manifest->>'status' is distinct from 'validated' or p_manifest#>>'{audit,complete}' is distinct from 'true'
 or coalesce(length(p_manifest#>>'{backup,hash}'),0)<>64 or not exists(select 1 from storage.objects where bucket_id='kickx-calculation-archives' and name=p_manifest#>>'{backup,path}')
 then raise exception 'VALUATION_VALIDATION_REQUIRED';end if;
 update public.kickx_policy set valuation_rebuild=p_manifest||jsonb_build_object('startsAt','2026-09-30T15:00:00Z') where id=true;
 return p_manifest;
end $$;
revoke all on function public.kickx_stage_valuation_rebuild(jsonb) from public,anon,authenticated;
grant execute on function public.kickx_stage_valuation_rebuild(jsonb) to service_role;
create function public.kickx_valuation_integrity() returns jsonb language sql stable set search_path='' as $$
 select jsonb_build_object(
 'wallets',(select md5(coalesce(string_agg(to_jsonb(w)::text,',' order by user_id),''))from public.wallets w),
 'holdings',(select md5(coalesce(string_agg(to_jsonb(h)::text,',' order by user_id,player_id),''))from public.holdings h),
 'trades',(select md5(coalesce(string_agg(to_jsonb(t)::text,',' order by id),''))from public.trades t))
$$;
revoke all on function public.kickx_valuation_integrity() from public,anon,authenticated;
grant execute on function public.kickx_valuation_integrity() to service_role;
create function public.kickx_valuation_data_audit() returns jsonb language sql stable set search_path='' as $$
 with finished as(select f.*,s.lineups,s.incidents,s.player_stats from public.fixtures f left join public.football_event_sources s on s.fixture_id=f.id
 where f.league_id in('bsd-1','bsd-3','bsd-4','bsd-5','bsd-6') and f.status='FT'),
 starters as(select f.id fixture_id,'bsd-'||(p->>'id') player_id from finished f cross join lateral jsonb_each(f.lineups->'lineups')side cross join lateral jsonb_array_elements(side.value->'players')p),
 gaps as(select f.id,count(*)filter(where s.player_id is not null and m.player_id is null) missing_starters from finished f left join starters s on s.fixture_id=f.id left join public.football_match_stats m on m.fixture_id=f.id and m.player_id=s.player_id group by f.id)
 select jsonb_build_object(
 'missingStarterStatistics',(select coalesce(sum(missing_starters),0)from gaps),
 'missingMatchSources',(select count(*)from finished where lineups is null or incidents is null),
 'unconfirmedLineups',(select count(*)from finished where lineups->>'lineup_status' is distinct from 'confirmed'),
 'missingIncidents',(select count(*)from finished where jsonb_typeof(incidents->'incidents') is distinct from 'array'),
 'missingMinutes',(select count(*)from public.football_match_stats m join finished f on f.id=m.fixture_id where m.stats->'minutes_played' is null or m.stats->'minutes_played'='null'::jsonb),
 'goalTimelineMismatch',(select count(*)from finished f where jsonb_typeof(incidents->'incidents')='array' and
 ((select count(*)from jsonb_array_elements(incidents->'incidents')e where e->>'type'='goal' and e->>'is_home'='true')is distinct from home_score::bigint or
 (select count(*)from jsonb_array_elements(incidents->'incidents')e where e->>'type'='goal' and e->>'is_home'='false')is distinct from away_score::bigint)),
 'missingCurrentRosterPosition',(select count(*)from public.players p join public.teams t on t.id=p.team_id where t.league_id in('bsd-1','bsd-3','bsd-4','bsd-5','bsd-6') and p.position is null),
 'repairFixtures',(select coalesce(jsonb_agg(id),'[]')from(select id from gaps where missing_starters>0 union select id from finished where lineups is null or incidents is null
 union select f.id from finished f where jsonb_typeof(incidents->'incidents')='array' and
 ((select count(*)from jsonb_array_elements(incidents->'incidents')e where e->>'type'='goal' and e->>'is_home'='true')is distinct from home_score::bigint or
 (select count(*)from jsonb_array_elements(incidents->'incidents')e where e->>'type'='goal' and e->>'is_home'='false')is distinct from away_score::bigint))q),
 'performanceStatuses',(select coalesce(jsonb_object_agg(status,n),'{}')from(select r.status,count(*)n from public.performance_results r join finished f on f.id=r.fixture_id group by r.status)q))
$$;
revoke all on function public.kickx_valuation_data_audit() from public,anon,authenticated;
grant execute on function public.kickx_valuation_data_audit() to service_role;
create function public.kickx_finish_valuation_rebuild() returns jsonb language plpgsql set search_path='' as $$
declare v jsonb;n integer;before_hash jsonb;begin
 perform public.kickx_economy_lock();select valuation_rebuild into v from public.kickx_policy;
 if v->>'status' is distinct from 'active' then return jsonb_build_object('pending','POLICY_NOT_ACTIVE');end if;
 if v ? 'portfolioRebuiltAt' then return jsonb_build_object('unchanged',true);end if;
 if exists(select 1 from public.holdings h join public.player_market_snapshots s on s.id=h.player_id where s.pricing_status<>'ready')then return jsonb_build_object('pending','HELD_PLAYER_DATA_INCOMPLETE');end if;
 before_hash:=public.kickx_valuation_integrity();
 update public.asset_snapshots a set value=public.kickx_assets_at(a.user_id,a.recorded_at) where a.recorded_at>=timestamptz '2026-09-30T15:00:00Z';
 get diagnostics n=row_count;
 perform public.kickx_auto_refresh_rankings();
 if before_hash is distinct from public.kickx_valuation_integrity()then raise exception 'VALUATION_FINANCIAL_INTEGRITY';end if;
 update public.kickx_policy set valuation_rebuild=valuation_rebuild||jsonb_build_object('portfolioRebuiltAt',clock_timestamp(),'assetSnapshotsRebuilt',n)where id=true;
 return jsonb_build_object('assetSnapshotsRebuilt',n);
end $$;
revoke all on function public.kickx_finish_valuation_rebuild() from public,anon,authenticated;
grant execute on function public.kickx_finish_valuation_rebuild() to service_role;
