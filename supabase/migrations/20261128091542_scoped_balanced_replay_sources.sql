-- Bound the evidence preflight to one league per request.
begin;
create or replace function public.kickx_balanced_stale_players(p_league text)returns setof text language sql stable set search_path='' set jit=off as $$
 with games as materialized(select f.*,s.updated_at source_updated_at,s.incidents @? '$.incidents[*] ? (@.type == "varDecision" && (@.decision == "cardUpgrade" || @.decision == "redCardGiven"))' var_terminal,public.kickx_observed_fixture_minutes(f.id) duration
 from public.fixtures f left join public.football_event_sources s on s.fixture_id=f.id
 where f.status='FT'and f.league_id=p_league and f.league_id in('bsd-1','bsd-3','bsd-4','bsd-5','bsd-6')and public.kickx_regular_fixture(f.id)is true),
 signatures as(select r.player_id,r.source_hash,md5((case when g.var_terminal
 then md5(md5(jsonb_build_array(m.updated_at,g.updated_at,g.source_updated_at,p.version,p.club_competitions_enabled,g.duration,'scoring-cache-v1')::text)||':var-terminal-20261030')
 else md5(jsonb_build_array(m.updated_at,g.updated_at,g.source_updated_at,p.version,p.club_competitions_enabled,g.duration,'scoring-cache-v1')::text)end)||(p.report_parameters->>'scoringRevision')) expected
 from public.performance_results r join games g on g.id=r.fixture_id join public.football_match_stats m using(player_id,fixture_id)cross join public.kickx_policy p where r.rule_version='report-v3')
 select distinct player_id from signatures where source_hash is distinct from expected order by player_id
$$;
revoke all on function public.kickx_balanced_stale_players(text)from public,anon,authenticated;
grant execute on function public.kickx_balanced_stale_players(text)to service_role;


notify pgrst,'reload schema';
commit;
