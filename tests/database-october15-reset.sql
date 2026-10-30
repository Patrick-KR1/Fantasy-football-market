begin;
create schema if not exists storage;
create table if not exists storage.objects(bucket_id text,name text,created_at timestamptz default now());
alter table storage.objects add column if not exists created_at timestamptz default now();
insert into storage.objects(bucket_id,name)values('kickx-calculation-archives','oct15-test/backup.json.gz');
update public.kickx_policy set version='report-v3',club_competitions_enabled=false,
 report_parameters=report_parameters||'{"initialMin":10000,"initialMax":1000000,"valuationStartMs":1790780400000}',
 report_reference='{"status":"ready","regularSeasonScopeVerified":true,"season":2025,"hash":"oct15-test","groups":{"DF":{"mean":6,"lower":0,"upper":30,"baselines":[4,6,8]}},"players":{"oct15-player":{"DF":{"n":10,"sum":60,"fixtures":[]}}}}';
update public.kickx_policy set report_reference=report_reference||jsonb_build_object('completed',1500,'fixtureCount',1500,
 'archives',(select jsonb_agg(jsonb_build_object('fixtureId','old-'||n,'path','oct15-test/backup.json.gz'))from generate_series(1,1500)n),
 'groups',jsonb_build_object('DF',report_reference#>'{groups,DF}','GK',report_reference#>'{groups,DF}','MF',report_reference#>'{groups,DF}','FW',report_reference#>'{groups,DF}'));
insert into public.leagues(id,name)values('bsd-1','October test')on conflict do nothing;
insert into public.teams(id,name,league_id)values('oct15-home','Home','bsd-1'),('oct15-away','Away','bsd-1');
insert into public.players(id,name,provider,position,team_id)values('oct15-player','Player','bsd','DF','oct15-home');
insert into public.player_market_snapshots(id,price,pricing_status,pricing_rule_version)values('oct15-player',1000000,'ready','report-v3');
insert into public.fixtures(id,league_id,home_team_id,away_team_id,starts_at,status,home_score,away_score,season,stage)
values('oct15-before','bsd-1','oct15-home','oct15-away','2026-10-14T12:00:00Z','FT',0,0,2026,'league-phase'),
('oct15-after','bsd-1','oct15-home','oct15-away','2026-10-15T12:00:00Z','FT',0,0,2026,'league-phase');
insert into public.football_match_stats(player_id,fixture_id,team_id,stats)
select 'oct15-player',id,'oct15-home','{"minutes_played":90}'from public.fixtures where id like 'oct15-%';
do $$declare answer jsonb;params jsonb;backup jsonb;reference jsonb;fingerprint jsonb;begin
 if has_function_privilege('anon','public.kickx_reset_october15_prices(jsonb,jsonb,jsonb)','execute')or
 has_function_privilege('authenticated','public.kickx_replay_cached_prices(integer)','execute')then raise exception 'Reset exposed';end if;
 fingerprint:=public.kickx_valuation_integrity();
 answer:=public.kickx_publish_calculation_delta(null,'oct15-player',public.kickx_calculation_token('oct15-player'),
 '[{"fixtureId":"oct15-before","position":"DF","score":8,"status":"provisional","ruleVersion":"report-v3","scoringRevision":"regular-season-20261030","breakdown":[],"warnings":[]},
 {"fixtureId":"oct15-after","position":"DF","score":10,"status":"provisional","ruleVersion":"report-v3","scoringRevision":"regular-season-20261030","breakdown":[],"warnings":[]}]');
 select report_parameters,report_reference||jsonb_build_object('hash',repeat('b',64),'scopeAudit',jsonb_build_object('previousReferenceBackup',jsonb_build_object('path','oct15-test/backup.json.gz'))) into params,reference from public.kickx_policy;
 begin
  perform public.kickx_reset_october15_prices(params,'{}',reference);raise exception 'Missing backup accepted';
 exception when others then if sqlerrm<>'RESET_VERIFIED_BACKUP_REQUIRED'then raise;end if;end;
 backup:=jsonb_build_object('path','oct15-test/backup.json.gz','hash',repeat('a',64),'bytes',100,'integrity',fingerprint);
 begin
  perform public.kickx_reset_october15_prices('{}',backup,reference);raise exception 'Stale policy accepted';
 exception when others then if sqlerrm<>'RESET_POLICY_CHANGED'then raise;end if;end;
 answer:=public.kickx_reset_october15_prices(params,backup,reference);
 if (select price from public.player_market_snapshots where id='oct15-player')<>100000 then raise exception 'Initial range not reset';end if;
 if exists(select 1 from public.player_price_results where player_id='oct15-player')then raise exception 'Old price steps survived';end if;
 if (select count(*)from public.price_history where player_id='oct15-player'and recorded_at=timestamptz '2026-10-14T15:00:00Z')<>1 then raise exception 'Wrong launch point';end if;
 answer:=public.kickx_replay_cached_prices(15);
 if (answer->>'processed')::integer<>1 then raise exception 'Cached evidence not replayed: %',answer;end if;
 if (select price from public.player_market_snapshots where id='oct15-player')<>102000 then raise exception 'Pre-launch prices compounded';end if;
 if (select count(*)from public.player_price_results where player_id='oct15-player')<>1 or
 not exists(select 1 from public.player_price_results where player_id='oct15-player'and fixture_id='oct15-after'and form_score=7)
 then raise exception 'Pre-launch form or price boundary incorrect';end if;
 if exists(select 1 from public.price_history where player_id='oct15-player'and recorded_at<timestamptz '2026-10-14T15:00:00Z')then raise exception 'Pre-launch chart point survived';end if;
 answer:=public.kickx_reset_october15_prices(params,backup,reference);
 if answer->>'unchanged' is distinct from 'true'or(select price from public.player_market_snapshots where id='oct15-player')<>102000 then raise exception 'Reset not idempotent';end if;
 if public.kickx_valuation_integrity()is distinct from fingerprint then raise exception 'Financial rows changed';end if;
end $$;
rollback;
