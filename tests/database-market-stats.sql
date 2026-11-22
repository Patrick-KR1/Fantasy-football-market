begin;
update public.kickx_policy set version='report-v3';
insert into public.leagues(id,name)values('bsd-1','Premier League')on conflict do nothing;
insert into public.teams(id,name,league_id)values('market-stats-home','Home','bsd-1'),('market-stats-away','Away','bsd-1');
insert into public.players(id,name,team_id,provider,position)values
 ('bsd-991001','Recorded scorer','market-stats-home','bsd','FW'),
 ('bsd-991002','Unknown records','market-stats-home','bsd','MF'),
 ('bsd-991003','Verified zero','market-stats-home','bsd','DF');
insert into public.fixtures(id,provider,league_id,home_team_id,away_team_id,starts_at,status,stage,season)values
 ('market-stats-one','bsd','bsd-1','market-stats-home','market-stats-away','2026-10-01','FT','league-phase',2026),
 ('market-stats-missing','bsd','bsd-1','market-stats-home','market-stats-away','2026-10-02','FT','league-phase',2026),
 ('market-stats-zero','bsd','bsd-1','market-stats-home','market-stats-away','2026-10-03','FT','league-phase',2026),
 ('market-stats-next','bsd','bsd-1','market-stats-home','market-stats-away','2026-10-04','FT','league-phase',2026),
 ('market-stats-old','bsd','bsd-1','market-stats-home','market-stats-away','2025-10-01','FT','league-phase',2025),
 ('market-stats-cup','bsd','bsd-1','market-stats-home','market-stats-away','2026-10-05','FT','final',2026),
 ('market-stats-live','bsd','bsd-1','market-stats-home','market-stats-away','2026-10-06','LIVE','league-phase',2026),
 ('market-stats-dnp','bsd','bsd-1','market-stats-home','market-stats-away','2026-10-07','FT','league-phase',2026);
insert into public.football_match_stats(player_id,fixture_id,team_id,stats,normalized)values
 ('bsd-991001','market-stats-one','market-stats-home','{"minutes_played":90}','{"values":{"minutes":90,"goals":2,"assists":1}}'),
 ('bsd-991001','market-stats-missing','market-stats-home','{"minutes_played":90}','{"values":{"minutes":90,"goals":null,"assists":null}}'),
 ('bsd-991001','market-stats-zero','market-stats-home','{"minutes_played":90}','{"values":{"minutes":90,"goals":0,"assists":0}}'),
 ('bsd-991001','market-stats-old','market-stats-home','{"minutes_played":90}','{"values":{"minutes":90,"goals":99,"assists":99}}'),
 ('bsd-991001','market-stats-cup','market-stats-home','{"minutes_played":90}','{"values":{"minutes":90,"goals":99,"assists":99}}'),
 ('bsd-991001','market-stats-live','market-stats-home','{"minutes_played":90}','{"values":{"minutes":90,"goals":99,"assists":99}}'),
 ('bsd-991001','market-stats-dnp','market-stats-home','{"minutes_played":0}','{"values":{"minutes":0,"goals":99,"assists":99}}'),
 ('bsd-991002','market-stats-one','market-stats-home','{"minutes_played":90}','{"values":{"minutes":90,"goals":null,"assists":null}}'),
 ('bsd-991003','market-stats-one','market-stats-home','{"minutes_played":90}','{"values":{"minutes":90,"goals":0,"assists":0}}');
insert into public.player_market_snapshots(id,price,performance,change_percent,performance_rule_version,pricing_rule_version,pricing_status)
 values('bsd-991001',125000,8,2,'report-v3','report-v3','ready');
select public.kickx_report_refresh_summaries();
do $$declare summary public.player_season_summaries%rowtype;begin
 select * into strict summary from public.player_season_summaries where id='bsd-991001';
 if summary.goals is distinct from 2 or summary.assists is distinct from 1 or summary.matches_imported<>3 or summary.season<>2026 then
  raise exception 'Confirmed totals lost or wrong matches included: %',row_to_json(summary);end if;
 if (select goals is not null or assists is not null from public.player_season_summaries where id='bsd-991002') then raise exception 'Unknown records became zero';end if;
 if not exists(select 1 from public.player_season_summaries where id='bsd-991003'and goals=0 and assists=0)then raise exception 'Verified zero lost';end if;
end $$;
-- Subsequent imports, repeated imports and provider corrections use the same sums.
set local role service_role;
do $$declare payload jsonb;begin
 payload:='{"provider":"bsd","matches":[{"player_id":"bsd-991001","fixture_id":"market-stats-next","team_id":"market-stats-home","stats":{"minutes_played":90},"normalized":{"values":{"minutes":90,"goals":1,"assists":2}}}]}';
 perform public.apply_bsd_batch(payload);
 perform public.apply_bsd_batch(payload);
 if not exists(select 1 from public.player_catalog where id='bsd-991001'and goals=3 and assists=3 and matches_imported=4)then raise exception 'Import hid or double-counted totals';end if;
 payload:=jsonb_set(payload,'{matches,0,normalized,values,goals}','0');
 perform public.apply_bsd_batch(payload);
 if not exists(select 1 from public.player_catalog where id='bsd-991001'and goals=2 and assists=3 and matches_imported=4)then raise exception 'Correction failed to replace totals';end if;
end $$;
reset role;
select public.kickx_report_refresh_summaries();
set local role anon;
do $$begin
 if not exists(select 1 from public.player_catalog where id='bsd-991001'and goals=2 and assists=3 and price=125000 and performance=8 and change_percent=2)then raise exception 'Catalog read differs or valuation changed';end if;
 if has_function_privilege('anon','public.apply_bsd_batch(jsonb)','execute')or has_function_privilege('anon','public.kickx_report_refresh_summaries()','execute')then raise exception 'Public summary write exposed';end if;
end $$;
reset role;
rollback;
