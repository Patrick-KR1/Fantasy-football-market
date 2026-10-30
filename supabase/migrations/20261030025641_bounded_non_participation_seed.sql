-- Private source checkpoint: prevents rescanning unchanged games or changing source timestamps.
alter table public.football_event_sources add column non_participation_seeded_at timestamptz;
create or replace function public.kickx_seed_non_participation() returns integer language plpgsql set search_path='' set jit=off as $$
declare inserted integer;affected text[];game_ids text[];begin
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('kickx:bsd-import',0));
 select array_agg(id) into game_ids from(select f.id from public.fixtures f join public.football_event_sources s on s.fixture_id=f.id
 where f.league_id in('bsd-1','bsd-3','bsd-4','bsd-5','bsd-6') and f.status='FT'
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

create function public.kickx_non_participation_work() returns jsonb language plpgsql set search_path='' set jit=off as $$
declare n integer;remaining integer;begin
 n:=public.kickx_seed_non_participation();
 select count(*) into remaining from public.fixtures f join public.football_event_sources s on s.fixture_id=f.id where f.league_id in('bsd-1','bsd-3','bsd-4','bsd-5','bsd-6') and f.status='FT'
 and f.starts_at>=timestamptz '2026-09-30T15:00:00Z'-interval '4 hours'
 and case when f.starts_at>=timestamptz '2026-09-30T15:00:00Z' then true else public.kickx_fixture_valuation_at(f.id)>=timestamptz '2026-09-30T15:00:00Z' end
 and s.lineups->>'lineup_status'='confirmed' and jsonb_typeof(s.incidents->'incidents')='array'
 and (s.non_participation_seeded_at is null or s.non_participation_seeded_at<s.updated_at);
 return jsonb_build_object('inserted',n,'remaining',remaining);
end $$;
revoke all on function public.kickx_non_participation_work() from public,anon,authenticated;
grant execute on function public.kickx_non_participation_work() to service_role;
