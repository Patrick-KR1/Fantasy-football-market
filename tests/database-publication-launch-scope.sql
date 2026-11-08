-- Exercise the real publisher: pre-launch errors, the end-time boundary,
-- complete/DNP prices, historical regressions and price-affecting regressions.
begin;
update public.kickx_policy set version='report-v3',club_competitions_enabled=false,
 report_parameters=report_parameters||'{"pricingModel":"position-points","initialMin":100000,"initialMax":100000,"minPrice":10000,"maxPrice":9007199254740991,"maxUp":0.1,"maxDown":0.1,"priceSensitivity":0.1,"priceUnit":100000,"valuationStartMs":1791990000000,"benchmarkCutoffMs":1791990000000,"positionBenchmarks":{"GK":8,"DF":8,"MF":8,"FW":8},"nonParticipationRate":0.015}',
 report_reference='{"status":"ready","season":2025,"hash":"publication-frozen","groups":{"MF":{"mean":8,"lower":0,"upper":30,"baselines":[8]}},"players":{}}';
insert into public.leagues(id,name)values('bsd-1','Publication league')on conflict do nothing;
insert into public.teams(id,name,league_id)values('publication-home','Home','bsd-1'),('publication-away','Away','bsd-1');
insert into public.players(id,name,provider,position,team_id)values
 ('publication-player','Player','bsd','MF','publication-home'),
 ('publication-new','New blocked player','bsd','MF','publication-home');
insert into public.fixtures(id,league_id,home_team_id,away_team_id,starts_at,finished_observed_at,status,season,stage)values
 ('publication-pre','bsd-1','publication-home','publication-away','2026-10-13T12:00Z','2026-10-13T13:45Z','FT',2026,'league-phase'),
 ('publication-before-edge','bsd-1','publication-home','publication-away','2026-10-14T13:15Z','2026-10-14T14:59:59.999Z','FT',2026,'league-phase'),
 ('publication-at-edge','bsd-1','publication-home','publication-away','2026-10-14T13:15Z','2026-10-14T15:00Z','FT',2026,'league-phase'),
 ('publication-dnp','bsd-1','publication-home','publication-away','2026-10-16T12:00Z','2026-10-16T13:45Z','FT',2026,'league-phase'),
 ('publication-played','bsd-1','publication-home','publication-away','2026-10-17T12:00Z','2026-10-17T13:45Z','FT',2026,'league-phase');
insert into public.football_match_stats(player_id,fixture_id,team_id,stats)
 select 'publication-player',id,'publication-home',jsonb_build_object('minutes_played',case when id='publication-dnp'then 0 else 90 end)
 from public.fixtures where id like 'publication-%'and id<>'publication-at-edge';
insert into public.football_match_stats(player_id,fixture_id,team_id,stats)
 values('publication-new','publication-at-edge','publication-home','{"minutes_played":90}');
insert into public.player_market_snapshots(id,price,pricing_rule_version,pricing_status)values
 ('publication-player',100000,'report-v3','pending'),('publication-new',100000,'report-v3','pending');
create function pg_temp.publication_results()returns jsonb language sql as $$
 select jsonb_agg(jsonb_build_object('fixtureId',fixture_id,'ruleVersion','report-v3','position','MF',
 'status',case when fixture_id in('publication-pre','publication-before-edge')then 'blocked'when fixture_id='publication-dnp'then 'not-played'else 'provisional'end,
 'score',case when fixture_id='publication-at-edge'then 8 when fixture_id='publication-played'then 12 else null end,
 'breakdown','[]'::jsonb,'warnings',case when fixture_id in('publication-pre','publication-before-edge')then '["GOAL_SCORE_MISMATCH"]'::jsonb else '[]'::jsonb end)order by fixture_id)
 from public.football_match_stats where player_id='publication-player'
$$;
create function pg_temp.publish_period(player text,hash text,results jsonb)returns jsonb language plpgsql as $$
declare expected jsonb;begin
 select jsonb_agg(jsonb_build_object('fixture',m.fixture_id,'statsAt',m.updated_at,'sourceAt',s.updated_at,'fixtureAt',f.updated_at)order by m.fixture_id)into expected
 from public.football_match_stats m join public.fixtures f on f.id=m.fixture_id left join public.football_event_sources s on s.fixture_id=f.id where m.player_id=player;
 return public.kickx_publish_calculation(null,player,hash,expected,results);
end $$;
do $$declare answer jsonb;results jsonb;initial jsonb;before_history jsonb;begin
 results:=pg_temp.publication_results();
 answer:=pg_temp.publish_period('publication-player','publication-first',results);
 if answer->>'withheld'='true'or answer->>'price'<>'103500'then raise exception 'Pre-launch errors withheld completed prices: %',answer;end if;
 if(select count(*)from public.player_price_results where player_id='publication-player')<>2 then raise exception 'Pre-launch error entered prices or DNP was omitted';end if;
 if not exists(select 1 from public.player_price_results where player_id='publication-player'and fixture_id='publication-dnp'and price_before=100000 and price_after=98500)then raise exception 'Verified DNP no longer reduced the preceding price by 1.5 percent';end if;
 if(select count(*)from public.performance_results where player_id='publication-player'and status='blocked')<>2 then raise exception 'Historical errors erased or fabricated as complete';end if;
 if(select count(*)from public.price_history where player_id='publication-player')<>3 then raise exception 'Launch point or completed price history missing';end if;
 select detail into initial from public.player_initial_values where player_id='publication-player';
 select jsonb_agg(jsonb_build_array(recorded_at,value)order by recorded_at)into before_history from public.price_history where player_id='publication-player';
 -- A formerly usable pre-launch score can become incomplete without changing
 -- the frozen baseline, asset price or post-launch chart.
 select jsonb_agg(case when x->>'fixtureId'='publication-pre'then x||'{"score":12,"status":"provisional","warnings":[]}'else x end)into results from jsonb_array_elements(results)x;
 answer:=pg_temp.publish_period('publication-player','publication-pre-recovered',results);
 answer:=pg_temp.publish_period('publication-player','publication-pre-regressed',pg_temp.publication_results());
 if answer->>'withheld'='true'or answer->>'price'<>'103500'then raise exception 'Historical regression blocked unrelated current prices: %',answer;end if;
 if initial is distinct from(select detail from public.player_initial_values where player_id='publication-player')then raise exception 'Frozen initial value changed';end if;
 if before_history is distinct from(select jsonb_agg(jsonb_build_array(recorded_at,value)order by recorded_at)from public.price_history where player_id='publication-player')then raise exception 'Historical regression changed current price history';end if;
 -- A never-scored match at the exact launch boundary must remain withheld,
 -- even though its kickoff preceded launch.
 answer:=pg_temp.publish_period('publication-new','publication-new-blocked',
 '[{"fixtureId":"publication-at-edge","position":"MF","score":null,"status":"blocked","ruleVersion":"report-v3","breakdown":[],"warnings":["GOAL_SCORE_MISMATCH"]}]');
 if answer->>'reason'is distinct from'LATEST_RESULT_INCOMPLETE'then raise exception 'Launch boundary error passed publication: %',answer;end if;
 if(select price from public.player_market_snapshots where id='publication-new')<>100000 then raise exception 'Withheld boundary match changed price';end if;
 -- Previously published post-launch scores retain the stronger correction guard.
 select jsonb_agg(case when x->>'fixtureId'='publication-played'then x||'{"score":null,"status":"blocked","warnings":["GOAL_SCORE_MISMATCH"]}'else x end)into results from jsonb_array_elements(pg_temp.publication_results())x;
 answer:=pg_temp.publish_period('publication-player','publication-post-regressed',results);
 if answer->>'reason'is distinct from'PREVIOUS_RESULT_NOW_INCOMPLETE'then raise exception 'Post-launch correction protection lost: %',answer;end if;
 if(select price from public.player_market_snapshots where id='publication-player')<>103500 then raise exception 'Incomplete correction erased published asset value';end if;
end $$;
rollback;
