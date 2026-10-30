begin;
do $$begin
 if has_function_privilege('anon','public.kickx_seed_non_participation()','execute') or has_function_privilege('authenticated','public.kickx_stage_valuation_rebuild(jsonb)','execute') then raise exception 'Rebuild helper exposed';end if;
 if has_table_privilege('anon','public.football_roster_observations','select') then raise exception 'Roster evidence exposed';end if;
 if has_column_privilege('anon','public.kickx_policy','valuation_rebuild','select')then raise exception 'Private rebuild descriptor exposed';end if;
 if has_function_privilege('anon','public.kickx_non_participation_work()','execute') or has_function_privilege('authenticated','public.kickx_non_participation_work()','execute')then raise exception 'Batch worker exposed';end if;
end $$;
create schema if not exists storage;
create table if not exists storage.objects(bucket_id text,name text);
insert into storage.objects(bucket_id,name)values('kickx-calculation-archives','valuation-test/private.json.gz');
do $$begin
 begin
  perform public.kickx_stage_valuation_rebuild('{"status":"validated","audit":{"complete":true},"backup":{"path":"valuation-test/private.json.gz"}}');
  raise exception 'Accepted a backup without integrity hash';
 exception when others then if sqlerrm<>'VALUATION_VALIDATION_REQUIRED'then raise;end if;end;
end $$;
insert into public.leagues(id,name)values('bsd-1','Valuation test')on conflict do nothing;
insert into public.teams(id,name,league_id)values('bsd-910','Home','bsd-1'),('bsd-911','Away','bsd-1');
insert into public.players(id,name,provider,position,team_id)values('bsd-9001','Bench','bsd','FW','bsd-910'),('bsd-9002','Unavailable','bsd','DF','bsd-910'),('bsd-9003','Later roster','bsd','MF','bsd-910');
insert into public.football_entity_sources(provider,kind,external_id,raw,updated_at)
values('bsd','squad',910,'{"team_id":910,"count":3,"players":[{"id":9001},{"id":9002},{"id":9003}]}','2026-10-03T00:00:00Z');
insert into public.fixtures(id,league_id,home_team_id,away_team_id,starts_at,status,home_score,away_score,season)
values('valuation-evidence','bsd-1','bsd-910','bsd-911','2026-10-02T12:00:00Z','FT',0,0,2026);
update public.fixtures set stage='league-phase' where id='valuation-evidence';
insert into public.football_event_sources(fixture_id,detail,lineups,incidents)
select 'valuation-evidence','{}',jsonb_build_object('lineup_status','confirmed','lineups',jsonb_build_object(
 'home',jsonb_build_object('team_id',910,'players',(select jsonb_agg(jsonb_build_object('id',n,'position','D'))from generate_series(100,110)n),'substitutes','[{"id":9001,"position":"F"}]'::jsonb),
 'away',jsonb_build_object('team_id',911,'players',(select jsonb_agg(jsonb_build_object('id',n,'position','D'))from generate_series(200,210)n),'substitutes','[]'::jsonb)),
 'unavailable_players','{"home":[{"id":9002}],"away":[]}'::jsonb),'{"incidents":[]}';
do $$declare n integer;begin
 n:=public.kickx_seed_non_participation();if n<>2 then raise exception 'Expected two verified DNPs, got %',n;end if;
 if exists(select 1 from public.football_match_stats where player_id='bsd-9003')then raise exception 'Current roster backdated';end if;
 if (select count(*)from public.calculation_queue where player_id in('bsd-9001','bsd-9002'))<>2 then raise exception 'DNP not queued';end if;
 if public.kickx_seed_non_participation()<>0 then raise exception 'DNP not idempotent';end if;
 if (select count(*)from public.player_match_records where fixture_id='valuation-evidence' and minutes=0)<>2 then raise exception 'DNP history absent';end if;
end $$;
-- The public chart must use the launch point and the game's completion, not today's replay time.
update public.kickx_policy set version='report-v3',club_competitions_enabled=false,
 report_parameters=report_parameters||'{"initialMin":100000,"initialMax":100000}',
 report_reference='{"status":"ready","season":2025,"hash":"valuation-test","groups":{"FW":{"mean":6,"lower":0,"upper":30,"baselines":[6]}} ,"players":{}}';
do $$declare answer jsonb;begin
 answer:=public.kickx_publish_calculation_delta(null,'bsd-9001',public.kickx_calculation_token('bsd-9001'),
 '[{"fixtureId":"valuation-evidence","position":"FW","score":null,"status":"not-played","ruleVersion":"report-v3","scoringRevision":"regular-season-20261030","breakdown":[],"warnings":[]}]');
 if (answer->>'price')::integer<>98500 then raise exception 'DNP publication price: %',answer;end if;
 if (select count(*)from public.price_history where player_id='bsd-9001')<>2 then raise exception 'Launch and DNP chart points missing';end if;
 if not exists(select 1 from public.price_history where player_id='bsd-9001' and recorded_at=timestamptz '2026-09-30T15:00:00Z' and value=100000) then raise exception 'Launch baseline missing';end if;
 if exists(select 1 from public.price_history where player_id='bsd-9001' and recorded_at>timestamptz '2026-10-03T00:00:00Z')then raise exception 'Replay date leaked into historical chart';end if;
 if (public.kickx_publish_calculation_delta(null,'bsd-9001',public.kickx_calculation_token('bsd-9001'),'[]')->>'unchanged')::boolean is distinct from true then raise exception 'DNP applied twice';end if;
end $$;
-- The production API processes at most eight games per transaction and resumes.
insert into public.fixtures(id,league_id,home_team_id,away_team_id,starts_at,status,home_score,away_score,season)
select 'valuation-batch-'||lpad(n::text,2,'0'),'bsd-1','bsd-910','bsd-911','2026-10-02T12:00:00Z','FT',0,0,2026 from generate_series(1,10)n;
update public.fixtures set stage='league-phase' where id like 'valuation-batch-%';
insert into public.football_event_sources(fixture_id,detail,lineups,incidents)
select f.id,s.detail,s.lineups,s.incidents from public.fixtures f cross join public.football_event_sources s where f.id like 'valuation-batch-%' and s.fixture_id='valuation-evidence';
do $$declare work jsonb;begin
 work:=public.kickx_non_participation_work();
 if (work->>'inserted')::integer<>16 or (work->>'remaining')::integer<>2 then raise exception 'First bounded batch: %',work;end if;
 work:=public.kickx_non_participation_work();
 if (work->>'inserted')::integer<>4 or (work->>'remaining')::integer<>0 then raise exception 'Batch did not resume: %',work;end if;
 if (public.kickx_non_participation_work()->>'inserted')::integer<>0 then raise exception 'Unchanged source reseeded';end if;
 if exists(select 1 from public.football_event_sources where fixture_id like 'valuation-batch-%' and non_participation_seeded_at is distinct from updated_at)then raise exception 'Seed checkpoint changed source timestamp';end if;
end $$;
rollback;
