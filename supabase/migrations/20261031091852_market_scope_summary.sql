begin;
-- The market and catalog share the current club's domestic-league cohort.
-- Batch active fixtures once instead of checking all fixtures per player.
create or replace function public.kickx_market_summary() returns jsonb
language sql stable security definer set search_path='' as $$
 with scoped as materialized (
  select p.id,p.team_id,p.trade_status,s.price,s.change_percent,s.pricing_status,s.updated_at
  from public.players p join public.teams t on t.id=p.team_id
  left join public.player_market_snapshots s on s.id=p.id
  where t.league_id in('bsd-1','bsd-3','bsd-4','bsd-5','bsd-6')
 ), active_fixtures as materialized (
  select f.id,f.home_team_id,f.away_team_id from public.fixtures f
  where f.league_id in('bsd-1','bsd-3','bsd-4','bsd-5','bsd-6')
   and now()>=f.starts_at-interval '90 minutes' and f.status not in('PST','CANC')
   and (f.status not in('FT','AET','PEN','AWD','WO') or f.finished_observed_at is null or now()<f.finished_observed_at+interval '10 minutes')
 ), locked as materialized (
  select p.id from scoped p join active_fixtures f on p.team_id in(f.home_team_id,f.away_team_id)
  union select m.player_id from public.football_match_stats m join active_fixtures f on f.id=m.fixture_id
 )
 select jsonb_build_object(
  'totalPlayers',count(*),
  'readyPlayers',count(*) filter(where price is not null and pricing_status='ready' and trade_status is null),
  'pricedPlayers',count(*) filter(where price is not null and pricing_status='ready' and trade_status is null and locked.id is null),
  'volume',(select count(*) from public.trades t join scoped p on p.id=t.player_id),
  'rising',count(*) filter(where pricing_status='ready' and change_percent>0),
  'falling',count(*) filter(where pricing_status='ready' and change_percent<0),
  'calculatedAt',max(updated_at)) from scoped left join locked on locked.id=scoped.id
$$;
revoke all on function public.kickx_market_summary() from public;
grant execute on function public.kickx_market_summary() to anon,authenticated;
notify pgrst,'reload schema';
commit;
