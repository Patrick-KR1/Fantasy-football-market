begin;
insert into public.leagues(id,name)values('bsd-1','League'),('bsd-7','Cup')on conflict do nothing;
insert into public.teams(id,name,league_id)values('market-open','Open','bsd-1'),('market-locked','Locked','bsd-1'),('market-away','Away','bsd-1'),('market-foreign','Outside','bsd-7');
insert into public.players(id,name,team_id,trade_status)values
 ('market-ready','Ready','market-open',null),('market-pending','Pending','market-open',null),
 ('market-disabled','Disabled','market-open','정지'),('market-null','No price','market-open',null),
 ('market-locked','Locked','market-locked',null),('market-evidence','Evidence','market-open',null),
 ('market-foreign','Outside','market-foreign',null),('market-unknown','No team',null,null);
insert into public.player_market_snapshots(id,price,pricing_status,change_percent,pricing_rule_version)values
 ('market-ready',100000,'ready',2,'report-v3'),('market-pending',100000,'pending',0,'report-v3'),('market-disabled',100000,'ready',0,'report-v3'),
 ('market-null',null,'pending',null,'report-v3'),('market-locked',100000,'ready',0,'report-v3'),('market-evidence',100000,'ready',0,'report-v3'),
 ('market-foreign',100000,'ready',99,'report-v3'),('market-unknown',100000,'ready',99,'report-v3');
insert into public.fixtures(id,league_id,home_team_id,away_team_id,starts_at,status)values
 ('market-active','bsd-1','market-locked','market-away',now()+interval '1 hour','NS'),
 ('market-cup','bsd-7','market-open','market-foreign',now()+interval '1 hour','NS');
insert into public.football_match_stats(player_id,fixture_id,team_id,stats)values('market-evidence','market-active','market-locked','{}');
set local role anon;
do $$declare s jsonb:=public.kickx_market_summary();begin
 if (s->>'totalPlayers')::int<>6 or(s->>'readyPlayers')::int<>3 or(s->>'pricedPlayers')::int<>1 or(s->>'rising')::int<>1 then raise exception 'Market cohort, readiness or lock mismatch: %',s;end if;
end $$;
reset role;
update public.fixtures set status='CANC' where id='market-active';
do $$declare s jsonb:=public.kickx_market_summary();begin
 if(s->>'pricedPlayers')::int<>3 then raise exception 'Cancelled match still locks players: %',s;end if;
end $$;
rollback;
