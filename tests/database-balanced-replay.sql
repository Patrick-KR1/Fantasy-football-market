begin;
create schema if not exists storage;
create table if not exists storage.buckets(id text primary key,public boolean not null default false);
create table if not exists storage.objects(bucket_id text,name text);
insert into storage.buckets(id,public)values('kickx-calculation-archives',false)on conflict do nothing;

insert into public.leagues(id,name)values('bsd-1','Premier League')on conflict(id)do nothing;
update public.kickx_policy set version='report-v3',report_reference='{"status":"ready","season":2025,"hash":"frozen","groups":{"FW":{"mean":6,"lower":-10,"upper":30,"baselines":[6]}}}',report_parameters='{"lambda":5,"kappa":4,"beta":0.3,"s":1,"deviationLimit":1,"initialMin":50000,"initialMax":150000,"minPrice":10000,"maxPrice":1000000,"maxUp":0.1,"maxDown":0.1,"nonParticipationRate":0.015,"lowerQuantile":0.05,"upperQuantile":0.95,"valuationStartMs":1791990000000,"neutralScore":6,"pointRate":0.025,"scoringRevision":"neutral-six-20261106"}';
insert into public.teams(id,name,league_id)values('add-home','Add home','bsd-1'),('add-away','Add away','bsd-1');
insert into public.players(id,name,position,team_id,provider)select 'add-'||p,p,p,'add-home','bsd'from unnest(array['GK','DF','MF','FW'])p;
insert into public.player_initial_values(player_id,rule_version,detail,input_hash)select id,'report-v3','{"season":2025,"price":100000,"seedScore":6,"lower":-10,"upper":30,"referenceHash":"frozen","fixtures":[]}',id from public.players where id like 'add-%';
insert into public.player_market_snapshots(id,price,pricing_status,pricing_rule_version)select id,100000,'ready','report-v3'from public.players where id like 'add-%';
insert into public.fixtures(id,league_id,home_team_id,away_team_id,starts_at,status,stage,season,home_score,away_score,observed_duration_minutes)
select 'add-before-'||n,'bsd-1','add-home','add-away',timestamptz '2026-09-01T12:00Z'+n*interval '1 day','FT','league-phase',2026,0,0,90 from generate_series(0,29)n
union all select 'add-after-'||n,'bsd-1','add-home','add-away',timestamptz '2026-10-15T12:00Z'+n*interval '1 day','FT','league-phase',2026,3,0,90 from generate_series(0,2)n;
insert into public.football_match_stats(player_id,fixture_id,team_id,stats)
select p.id,f.id,'add-home',case when f.id='add-after-2'then '{"minutes_played":0}'::jsonb else '{"minutes_played":90,"accurate_pass":40,"total_pass":50,"ball_recovery":4,"total_clearance":4,"won_contest":2,"outfielder_block":1,"was_fouled":2,"good_high_claim":1,"accurate_keeper_sweeper":1}'::jsonb end
from public.players p cross join public.fixtures f where p.id like 'add-%'and f.id like 'add-%';
insert into public.performance_results(player_id,fixture_id,score,status,rule_version,input_hash,position,breakdown,warnings)
select m.player_id,m.fixture_id,case when m.fixture_id='add-after-2'then null else 10 end,case when m.fixture_id='add-after-2'then 'not-played'else 'provisional'end,'report-v3',m.player_id||m.fixture_id,case when m.fixture_id='add-after-2'then null else p.position end,
case when m.fixture_id='add-after-2'then '[]'::jsonb else jsonb_build_array(jsonb_build_object('metric','goals','value',case when m.fixture_id='add-after-0'then 3 else 0 end,'points',0))||'[{"metric":"minutes","value":90,"points":6,"evidence":"old"}]'::jsonb||case when p.position<>'FW'then jsonb_build_array(jsonb_build_object('metric','clean_sheet','value',1,'points',1))else '[]'::jsonb end||'[{"metric":"score_range","value":20,"points":-10}]'::jsonb end,'[]'
from public.football_match_stats m join public.players p on p.id=m.player_id where p.id like 'add-%';
insert into public.player_match_records(player_id,fixture_id,played_at,opponent,minutes,performance,rule_version)select m.player_id,m.fixture_id,f.starts_at,'Add away',(m.stats->>'minutes_played')::integer,r.score,'report-v3'from public.football_match_stats m join public.fixtures f on f.id=m.fixture_id join public.performance_results r using(player_id,fixture_id)where m.player_id like 'add-%';
-- A roster-only player can have a frozen initial price and an empty revision.
insert into public.players(id,name,position,team_id,provider)values('idle-balanced','No appearances','FW','add-home','bsd');
insert into public.player_initial_values(player_id,rule_version,detail,input_hash)values('idle-balanced','report-v3','{"season":2025,"price":100000,"seedScore":6,"lower":-10,"upper":30,"referenceHash":"frozen","fixtures":[]}','idle');
insert into public.player_market_snapshots(id,price,pricing_status,pricing_rule_version)values('idle-balanced',100000,'ready','report-v3');
insert into public.calculation_revisions(player_id,input_hash,rule_version,results,new_price)values('idle-balanced','idle','report-v3','[]',100000);
do $$declare answer jsonb;state jsonb;integrity jsonb:=public.kickx_valuation_integrity();old_price numeric;path text:='performance-rebalance/report-balanced-20261128/'||repeat('a',64)||'.json.gz';begin
 perform kickx_private.apply_additive_assessments(integrity);
 update public.kickx_policy set report_parameters=report_parameters||'{"pricingModel":"position-points","priceUnit":100000}';
 -- A stale correction is not rebranded as verified evidence or forced ready.
 update public.football_match_stats set stats=stats||'{"fouls":4}',updated_at=clock_timestamp()where player_id='add-MF'and fixture_id='add-after-1';
 select price into old_price from public.player_market_snapshots where id='add-MF';
 state:=public.kickx_balanced_replay_state();
 begin perform kickx_private.apply_balanced_assessments('{}',path);raise exception 'Missing source guard';exception when others then if sqlerrm<>'BALANCED_SOURCE_CHANGED'then raise;end if;end;
 begin perform kickx_private.apply_balanced_assessments(state,path);raise exception 'Missing backup guard';exception when others then if sqlerrm<>'BALANCED_VERIFIED_BACKUP_REQUIRED'then raise;end if;end;
 insert into storage.objects(bucket_id,name)values('kickx-calculation-archives',path);
 answer:=kickx_private.apply_balanced_assessments(state,path);
 if (select results from public.calculation_revisions where player_id='idle-balanced')is distinct from'[]'::jsonb then raise exception 'Empty results changed';end if;
 if answer->>'scores'<>'127'then raise exception 'Balanced replay count %',answer;end if;
 if answer#>>'{positionBenchmarks,FW}'<>'7.000000'then raise exception 'Balanced fixed benchmark %',answer;end if;
 if (select report_parameters->>'pricingModel'from public.kickx_policy)<>'position-points'then raise exception 'Pricing algorithm changed';end if;
 if (select pricing_status from public.player_market_snapshots where id='add-MF')<>'pending'or(select price from public.player_market_snapshots where id='add-MF')<>old_price then raise exception 'Incomplete correction changed price';end if;
 if exists(select 1 from public.performance_results where player_id='add-FW'and breakdown @> '[{"metric":"passes_completed"}]')then raise exception 'Volume bonus remains';end if;
 if exists(select 1 from public.kickx_calculation_sources('add-FW')where not cached)then raise exception 'Replay source signature differs';end if;
 if not exists(select 1 from public.kickx_balanced_stale_players()x where x='add-MF')then raise exception 'Stale correction was marked fresh';end if;
 if public.kickx_valuation_integrity()is distinct from integrity then raise exception 'Financial state changed';end if;
 if (state->'initial')is distinct from(public.kickx_balanced_replay_state()->'initial')then raise exception 'Frozen initial values changed';end if;
 if exists(select 1 from public.price_history where player_id like 'add-%'and recorded_at<timestamptz '2026-10-14T15:00Z')then raise exception 'Prelaunch prices published';end if;
 if kickx_private.apply_balanced_assessments('{}',path)->>'unchanged'<>'true'then raise exception 'Duplicate replay';end if;
 if has_function_privilege('service_role','kickx_private.apply_balanced_assessments(jsonb,text)','execute')or has_function_privilege('anon','public.kickx_balanced_replay_state()','execute')then raise exception 'Privileged replay exposed';end if;
end $$;
rollback;
