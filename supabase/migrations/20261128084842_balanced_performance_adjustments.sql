-- Install only. The active scoring policy is unchanged until a verified private
-- backup and a compatible application deployment precede the explicit replay.
begin;
set local lock_timeout='3s';

create function kickx_private.balanced_number(v jsonb,signed boolean default false,integer_only boolean default true)
returns numeric language sql immutable set search_path='' as $$
 select case when jsonb_typeof(v)='number' then case
  when abs(v::text::numeric)<=9007199254740991
   and(signed or v::text::numeric>=0)
   and(not integer_only or v::text::numeric=trunc(v::text::numeric))
  then v::text::numeric end end
$$;
create function kickx_private.balanced_round(v numeric,places integer default 2)
returns numeric language sql immutable set search_path='' as $$
 select floor(v*power(10::numeric,places)+.500000001)/power(10::numeric,places)
$$;

create function kickx_private.balanced_adjustments(p_stats jsonb,p_scored numeric,p_position text)
returns jsonb language plpgsql immutable set search_path='' set jit=off as $$
declare parts jsonb:='[]';warnings jsonb:='[]';attempts numeric;completed numeric;xg numeric;n numeric;points numeric;loss numeric;item record;begin
 attempts:=kickx_private.balanced_number(p_stats->'total_pass');
 completed:=kickx_private.balanced_number(p_stats->'accurate_pass');
 if attempts is not null and completed is not null and completed>attempts then
  return jsonb_build_object('breakdown',parts,'warnings',warnings,'invalidPass',true);
 end if;
 if attempts>0 and completed is not null then
  points:=greatest(-2::numeric,least(2::numeric,(completed/attempts-.8)*10))*least(attempts/20,1);
  parts:=parts||jsonb_build_array(jsonb_build_object('metric','pass_accuracy','value',kickx_private.balanced_round(completed/attempts*100,6),
   'points',kickx_private.balanced_round(points),'evidence','accurate_pass / total_pass ('||trunc(completed)::text||'/'||trunc(attempts)::text||'); baseline=80%; full sample=20; cap=2'));
 else warnings:=warnings||'"pass_accuracy:UNVERIFIED_OR_THRESHOLD_NOT_MET"'::jsonb;end if;
 xg:=kickx_private.balanced_number(p_stats->'expected_goals',false,false);
 if xg is null then warnings:=warnings||'"xg_underperformance:UNVERIFIED_OR_MISSING_EXCLUDED"'::jsonb;
 elsif xg>0 then
  loss:=greatest(0,xg-p_scored);
  parts:=parts||jsonb_build_array(jsonb_build_object('metric','xg_underperformance','value',kickx_private.balanced_round(loss,6),'points',kickx_private.balanced_round(loss*-2),'evidence','max(expected_goals - verified goals, 0)'));
 end if;
 for item in select * from(values
  ('big_chance_missed',-1::numeric),('error_lead_to_a_goal',-3::numeric),('error_lead_to_a_shot',-1::numeric),
  ('dispossessed',-.2::numeric),('possession_lost',-.05::numeric),('unsuccessful_touch',-.1::numeric),
  ('duel_lost',-.1::numeric),('aerial_lost',-.1::numeric),('fouls',-.25::numeric))x(field,weight) loop
  n:=kickx_private.balanced_number(p_stats->item.field);
  if n is null then warnings:=warnings||to_jsonb(item.field||':UNVERIFIED_OR_MISSING_EXCLUDED');
  elsif n>0 then parts:=parts||jsonb_build_array(jsonb_build_object('metric',item.field,'value',n,'points',kickx_private.balanced_round(n*item.weight),'evidence',item.field));end if;
 end loop;
 if p_position='GK' then
  n:=kickx_private.balanced_number(p_stats->'goals_prevented',true,false);
  if n is null then warnings:=warnings||'"goals_prevented:UNVERIFIED_OR_MISSING_EXCLUDED"'::jsonb;
  elsif n<>0 then parts:=parts||jsonb_build_array(jsonb_build_object('metric','goals_prevented','value',kickx_private.balanced_round(n,6),'points',kickx_private.balanced_round(n),'evidence','goals_prevented; signed goalkeeper contribution'));end if;
 end if;
 return jsonb_build_object('breakdown',parts,'warnings',warnings,'invalidPass',false);
end $$;

create function kickx_private.balanced_result(p_breakdown jsonb,p_warnings jsonb,p_stats jsonb,p_position text)
returns jsonb language plpgsql immutable set search_path='' set jit=off as $$
declare extra jsonb;parts jsonb;warnings jsonb;goals numeric;score numeric;
 excluded text[]:=array['score_range','passes_completed','pass_accuracy','xg_underperformance','big_chance_missed','error_lead_to_a_goal','error_lead_to_a_shot','dispossessed','possession_lost','unsuccessful_touch','duel_lost','aerial_lost','fouls','goals_prevented'];
begin
 if jsonb_typeof(p_breakdown) is distinct from 'array' or not exists(select 1 from jsonb_array_elements(p_breakdown)b where b->>'metric'='goals')then raise exception 'VERIFIED_BREAKDOWN_REQUIRED';end if;
 select(b->>'value')::numeric into goals from jsonb_array_elements(p_breakdown)b where b->>'metric'='goals' limit 1;
 extra:=kickx_private.balanced_adjustments(p_stats,goals,p_position);
 if(extra->>'invalidPass')::boolean then raise exception 'INVALID_PASS_TOTALS';end if;
 select coalesce(jsonb_agg(b order by ord),'[]')into parts from jsonb_array_elements(p_breakdown)with ordinality x(b,ord)where not(b->>'metric'=any(excluded));
 parts:=parts||(extra->'breakdown');
 select coalesce(jsonb_agg(w order by ord),'[]')into warnings from jsonb_array_elements(coalesce(p_warnings,'[]'))with ordinality x(w,ord)
  where not(split_part(w#>>'{}',':',1)=any(excluded))and w#>>'{}'<>'BSD_OPTIONAL_METRICS_PROVISIONAL';
 warnings:=warnings||(extra->'warnings')||'"BSD_OPTIONAL_METRICS_PROVISIONAL"'::jsonb;
 select kickx_private.balanced_round(sum((b->>'points')::numeric))into score from jsonb_array_elements(parts)b;
 return jsonb_build_object('breakdown',parts,'warnings',warnings,'score',score);
end $$;
revoke all on function kickx_private.balanced_number(jsonb,boolean,boolean),kickx_private.balanced_round(numeric,integer),kickx_private.balanced_adjustments(jsonb,numeric,text),kickx_private.balanced_result(jsonb,jsonb,jsonb,text)from public,anon,authenticated,service_role;

-- Bounded-size metadata fingerprints detect collection, pricing, policy or
-- trade changes during the multi-page backup without rereading raw JSON blobs.
create function public.kickx_balanced_replay_state()returns jsonb language sql stable set search_path='' set jit=off set timezone='UTC' as $$
 select jsonb_build_object(
 'financial',public.kickx_valuation_integrity(),
 'policy',(select md5(jsonb_build_array(version,report_parameters,report_reference->>'hash')::text)from public.kickx_policy),
 'sources',(select md5(string_agg(player_id||'|'||fixture_id||'|'||updated_at::text,','order by player_id,fixture_id))from public.football_match_stats),
 'fixtures',(select md5(string_agg(id||'|'||updated_at::text,','order by id))from public.fixtures),
 'eventSources',(select md5(string_agg(fixture_id||'|'||updated_at::text,','order by fixture_id))from public.football_event_sources),
 'scores',(select md5(string_agg(player_id||'|'||fixture_id||'|'||coalesce(input_hash,'')||'|'||calculated_at::text,','order by player_id,fixture_id))from public.performance_results),
 'revisions',(select md5(string_agg(id::text||'|'||input_hash||'|'||coalesce(archive_path,'')||'|'||coalesce(archived_at::text,''),','order by id))from public.calculation_revisions),
 'initial',(select md5(string_agg(player_id||'|'||detail::text,','order by player_id))from public.player_initial_values)
 )
$$;
revoke all on function public.kickx_balanced_replay_state()from public,anon,authenticated;
grant execute on function public.kickx_balanced_replay_state()to service_role;


-- Repair already stale base evidence with the ordinary calculator before backup.
create function public.kickx_balanced_stale_players()returns setof text language sql stable set search_path='' set jit=off as $$
 with games as materialized(select f.*,s.updated_at source_updated_at,s.incidents,public.kickx_observed_fixture_minutes(f.id) duration
 from public.fixtures f left join public.football_event_sources s on s.fixture_id=f.id
 where f.status='FT'and f.league_id in('bsd-1','bsd-3','bsd-4','bsd-5','bsd-6')and public.kickx_regular_fixture(f.id)is true),
 signatures as(select r.player_id,r.source_hash,md5((case when g.incidents @? '$.incidents[*] ? (@.type == "varDecision" && (@.decision == "cardUpgrade" || @.decision == "redCardGiven"))'
 then md5(md5(jsonb_build_array(m.updated_at,g.updated_at,g.source_updated_at,p.version,p.club_competitions_enabled,g.duration,'scoring-cache-v1')::text)||':var-terminal-20261030')
 else md5(jsonb_build_array(m.updated_at,g.updated_at,g.source_updated_at,p.version,p.club_competitions_enabled,g.duration,'scoring-cache-v1')::text)end)||(p.report_parameters->>'scoringRevision')) expected
 from public.performance_results r join games g on g.id=r.fixture_id join public.football_match_stats m using(player_id,fixture_id)cross join public.kickx_policy p where r.rule_version='report-v3')
 select distinct player_id from signatures where source_hash is distinct from expected order by player_id
$$;
revoke all on function public.kickx_balanced_stale_players()from public,anon,authenticated;
grant execute on function public.kickx_balanced_stale_players()to service_role;

-- Explicit operator-only activation after a verified private backup and app rollout.
create function kickx_private.apply_balanced_assessments(p_expected_state jsonb,p_backup_path text) returns jsonb
language plpgsql security invoker set search_path='' set jit=off set enable_hashagg=off set timezone='UTC' as $$
declare before_hash jsonb;after_state jsonb;changed integer;price_count integer;refs jsonb;sample_counts jsonb;begin
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('kickx:bsd-import',0));perform public.kickx_economy_lock();
 if exists(select 1 from public.kickx_policy where report_parameters->>'scoringRevision'='report-balanced-20261128')then return '{"unchanged":true}';end if;
 before_hash:=public.kickx_balanced_replay_state();
 if before_hash is distinct from p_expected_state then raise exception 'BALANCED_SOURCE_CHANGED';end if;
 if p_backup_path is null or p_backup_path !~ '^performance-rebalance/report-balanced-20261128/[0-9a-f]{64}\.json\.gz$'
  or not exists(select 1 from storage.objects o join storage.buckets b on b.id=o.bucket_id where b.id='kickx-calculation-archives'and not b.public and o.name=p_backup_path)then raise exception 'BALANCED_VERIFIED_BACKUP_REQUIRED';end if;
 if not exists(select 1 from public.kickx_policy where version='report-v3'and report_parameters->>'valuationStartMs'='1791990000000'
  and report_parameters->>'scoringRevision'='report-additive-20261106'and report_parameters->>'pricingModel'='position-points')then raise exception 'RESET_POLICY_REQUIRED';end if;
 create temporary table balanced_games on commit drop as
 select f.*,s.updated_at source_updated_at,s.incidents,public.kickx_fixture_valuation_at(f.id) ended_at,public.kickx_observed_fixture_minutes(f.id) scoring_duration
 from public.fixtures f left join public.football_event_sources s on s.fixture_id=f.id
 where f.status='FT'and f.league_id in('bsd-1','bsd-3','bsd-4','bsd-5','bsd-6')and public.kickx_regular_fixture(f.id)is true
 and exists(select 1 from public.performance_results r where r.fixture_id=f.id and r.rule_version='report-v3');
 create unique index on pg_temp.balanced_games(id);
 -- Only reuse verified base evidence whose source signature still matches.
 create temporary table balanced_sources on commit drop as
 select r.player_id,r.fixture_id,r.status,r.source_hash=md5(h.signature||'report-additive-20261106') fresh,
 md5(h.signature||'report-balanced-20261128') next_hash
 from public.performance_results r join pg_temp.balanced_games g on g.id=r.fixture_id join public.football_match_stats m using(player_id,fixture_id)
 cross join public.kickx_policy p cross join lateral(select case when g.incidents @? '$.incidents[*] ? (@.type == "varDecision" && (@.decision == "cardUpgrade" || @.decision == "redCardGiven"))'
 then md5(md5(jsonb_build_array(m.updated_at,g.updated_at,g.source_updated_at,p.version,p.club_competitions_enabled,g.scoring_duration,'scoring-cache-v1')::text)||':var-terminal-20261030')
 else md5(jsonb_build_array(m.updated_at,g.updated_at,g.source_updated_at,p.version,p.club_competitions_enabled,g.scoring_duration,'scoring-cache-v1')::text)end signature)h where r.rule_version='report-v3';
 create unique index on pg_temp.balanced_sources(player_id,fixture_id);
 create temporary table balanced_scores on commit drop as
 select r.player_id,r.fixture_id,kickx_private.balanced_result(r.breakdown,r.warnings,m.stats,r.position) result
 from public.performance_results r join pg_temp.balanced_sources c using(player_id,fixture_id)join public.football_match_stats m using(player_id,fixture_id)
 where c.fresh and r.status in('ready','provisional')and r.score is not null;
 create unique index on pg_temp.balanced_scores(player_id,fixture_id);
 update public.performance_results r set breakdown=c.result->'breakdown',warnings=c.result->'warnings',score=(c.result->>'score')::numeric,
 input_hash=md5(jsonb_build_array('report-balanced-20261128',c.result,r.source_hash)::text),calculated_at=clock_timestamp()
 from pg_temp.balanced_scores c where r.player_id=c.player_id and r.fixture_id=c.fixture_id;
 get diagnostics changed=row_count;
 select jsonb_object_agg(position,mean_score),jsonb_object_agg(position,n)into refs,sample_counts from(
 select r.position,round(avg(r.score),6)mean_score,count(*)n from public.performance_results r join pg_temp.balanced_games g on g.id=r.fixture_id join pg_temp.balanced_scores c using(player_id,fixture_id)
 where r.rule_version='report-v3'and r.status in('ready','provisional')and r.score is not null and g.ended_at<timestamptz '2026-10-14T15:00:00Z'
 and g.season=(select (report_reference->>'season')::integer+1 from public.kickx_policy) group by r.position)q;
 if refs is null or (select count(*)from jsonb_object_keys(refs))<>4 or exists(select 1 from jsonb_each_text(refs)where value::numeric<=0)or exists(select 1 from jsonb_each_text(sample_counts)where value::integer<30)then raise exception 'INSUFFICIENT_PRELAUNCH_BENCHMARK';end if;
 update public.kickx_policy set report_parameters=report_parameters||jsonb_build_object('positionBenchmarks',refs,'benchmarkCounts',sample_counts,'scoringRevision','report-balanced-20261128')where id=true;
 update public.performance_results r set source_hash=c.next_hash from pg_temp.balanced_sources c
 where r.player_id=c.player_id and r.fixture_id=c.fixture_id and c.fresh
 and(r.status in('not-played','blocked')or exists(select 1 from pg_temp.balanced_scores x where x.player_id=r.player_id and x.fixture_id=r.fixture_id));
 update public.player_match_records m set performance=r.score,rule_version=r.rule_version from public.performance_results r where r.player_id=m.player_id and r.fixture_id=m.fixture_id and r.rule_version='report-v3'and exists(select 1 from pg_temp.balanced_scores c where c.player_id=r.player_id and c.fixture_id=r.fixture_id);
 create temporary table balanced_plans on commit drop as
 with results as materialized(select r.player_id,jsonb_agg(jsonb_build_object('fixtureId',r.fixture_id,'score',r.score,'status',r.status,'position',r.position,'season',f.season,
 'minutes',m.stats->'minutes_played','startedAt',f.starts_at,'endedAt',f.ended_at))items from public.performance_results r join pg_temp.balanced_games f on f.id=r.fixture_id
 join public.football_match_stats m using(player_id,fixture_id)where r.rule_version='report-v3'and f.ended_at>=timestamptz '2026-10-14T15:00:00Z'group by r.player_id)
 select i.player_id,public.kickx_report_plan(coalesce(r.items,'[]'),i.detail,p.report_parameters)plan from public.player_initial_values i cross join public.kickx_policy p left join results r on r.player_id=i.player_id
 where i.rule_version='report-v3'and i.detail is not null
 and exists(select 1 from public.player_market_snapshots s where s.id=i.player_id and s.pricing_status='ready')
 and not exists(select 1 from public.football_match_stats m join pg_temp.balanced_games g on g.id=m.fixture_id
 left join public.performance_results r using(player_id,fixture_id)left join pg_temp.balanced_sources c using(player_id,fixture_id)
 where m.player_id=i.player_id and g.ended_at>=timestamptz '2026-10-14T15:00:00Z'
 and(c.fresh is distinct from true or r.status not in('ready','provisional','not-played')));
 delete from public.player_price_results r using pg_temp.balanced_plans p where r.player_id=p.player_id;
 insert into public.player_price_results(player_id,fixture_id,rule_version,played_at,price_before,price_after,target_price,form_score,change_percent,window_fixture_ids,input_hash)
 select p.player_id,x->>'fixtureId','report-v3',(x->>'playedAt')::timestamptz,(x->>'priceBefore')::bigint,(x->>'priceAfter')::bigint,(x->>'targetPrice')::bigint,(x->>'formScore')::numeric,(x->>'changePercent')::numeric,x->'window',r.input_hash
 from pg_temp.balanced_plans p cross join lateral jsonb_array_elements(plan->'steps')x join public.performance_results r on r.player_id=p.player_id and r.fixture_id=x->>'fixtureId';
 get diagnostics price_count=row_count;
 delete from public.price_history h using pg_temp.balanced_plans p where h.player_id=p.player_id;
 insert into public.price_history(player_id,recorded_at,value,rule_version)
 select p.player_id,timestamptz '2026-10-14T15:00:00Z',(plan#>>'{baseline,price}')::numeric,'report-v3'from pg_temp.balanced_plans p
 union all select p.player_id,(x->>'playedAt')::timestamptz,(x->>'priceAfter')::numeric,'report-v3'from pg_temp.balanced_plans p cross join lateral jsonb_array_elements(plan->'steps')x;
 update public.player_market_snapshots s set performance_rule_version='report-v3',pricing_rule_version='report-v3',price=(p.plan->>'price')::numeric,change_percent=coalesce((p.plan#>>'{steps,-1,changePercent}')::numeric,0),
 performance=(select case when r.status='not-played'then null else r.score end from public.performance_results r join pg_temp.balanced_games f on f.id=r.fixture_id where r.player_id=s.id and r.status in('ready','provisional','not-played')order by f.starts_at desc,f.id desc limit 1),updated_at=clock_timestamp()
 from pg_temp.balanced_plans p where p.player_id=s.id;
 -- Reuse the latest full derived revision; do not append thousands of duplicate plans.
 update public.calculation_revisions c set pricing=p.plan,new_price=(p.plan->>'price')::bigint,input_hash=md5(p.player_id||':report-balanced-20261128'),
 results=(select jsonb_agg(jsonb_build_object('fixtureId',r.fixture_id,'score',r.score,'status',r.status,'position',r.position,'ruleVersion',r.rule_version,'scoringRevision','report-balanced-20261128','breakdown',r.breakdown,'warnings',r.warnings)order by f.starts_at,f.id)
 from public.performance_results r join public.fixtures f on f.id=r.fixture_id where r.player_id=p.player_id and r.rule_version='report-v3')
 from pg_temp.balanced_plans p where c.id=(select x.id from public.calculation_revisions x where x.player_id=p.player_id and x.rule_version='report-v3'and x.archive_path is null order by x.created_at desc,x.id desc limit 1);
 delete from public.player_calculation_state c where exists(select 1 from pg_temp.balanced_sources b where b.player_id=c.player_id);
 -- Incomplete corrections keep their previous market price and enter normal recalculation.
 update public.player_market_snapshots s set pricing_status='pending'
 where not exists(select 1 from pg_temp.balanced_plans p where p.player_id=s.id)and exists(select 1 from pg_temp.balanced_sources b where b.player_id=s.id);
 perform public.kickx_queue_player(q.player_id)from(select distinct player_id from pg_temp.balanced_sources)q;
 update public.asset_snapshots a set value=public.kickx_assets_at(a.user_id,a.recorded_at)where a.recorded_at>=timestamptz '2026-10-14T15:00:00Z';
 perform public.kickx_auto_refresh_rankings();
 after_state:=public.kickx_balanced_replay_state();
 if (before_hash-'policy'-'scores'-'revisions')is distinct from(after_state-'policy'-'scores'-'revisions')then raise exception 'BALANCED_SOURCE_OR_FINANCIAL_INTEGRITY';end if;
 if exists(select 1 from public.price_history where rule_version='report-v3'and recorded_at<timestamptz '2026-10-14T15:00:00Z')then raise exception 'PRELAUNCH_PRICE_EVENT';end if;
 insert into public.operation_audit(action,detail)values('policy.report-balanced',jsonb_build_object('scores',changed,'priceSteps',price_count,'positionBenchmarks',refs,'benchmarkCounts',sample_counts,'financialIntegrityUnchanged',true,'providerRequests',0,'backupPath',p_backup_path,'deferredPlayers',(select count(*)from public.player_market_snapshots where pricing_status='pending')));
 return jsonb_build_object('scores',changed,'priceSteps',price_count,'players',(select count(*)from pg_temp.balanced_plans),'positionBenchmarks',refs,'benchmarkCounts',sample_counts,'financialIntegrityUnchanged',true,'providerRequests',0,'backupPath',p_backup_path,'deferredPlayers',(select count(*)from public.player_market_snapshots where pricing_status='pending'));
end $$;
revoke all on function kickx_private.apply_balanced_assessments(jsonb,text)from public,anon,authenticated,service_role;

notify pgrst,'reload schema';
commit;
