-- Configuration and guarded helpers only. The approved reset requires a private,
-- verified backup; applying this migration alone does not erase market data.
begin;
alter table public.kickx_policy alter column report_parameters set default '{"lambda":5,"kappa":4,"beta":0.3,"s":1,"deviationLimit":1,"initialMin":50000,"initialMax":150000,"minPrice":10000,"maxPrice":1000000,"maxUp":0.02,"maxDown":0.02,"nonParticipationRate":0.015,"lowerQuantile":0.05,"upperQuantile":0.95,"valuationStartMs":1791990000000}';

-- All rebuild entry points must follow the configured launch, including future
-- roster checks and reference corrections. Preserve their existing protections.
do $$declare signature text;definition text;begin
 foreach signature in array array['kickx_stage_valuation_rebuild(jsonb)','kickx_finish_valuation_rebuild()',
 'kickx_non_participation_work()','kickx_replace_regular_reference(text,jsonb)',
 'kickx_seed_non_participation()','kickx_activate_report_policy()']loop
  definition:=pg_get_functiondef(('public.'||signature)::regprocedure);
  if position('timestamptz ''2026-09-30T15:00:00Z''' in definition)>0 then
   definition:=replace(definition,'timestamptz ''2026-09-30T15:00:00Z''',
    '(select to_timestamp((report_parameters->>''valuationStartMs'')::numeric/1000) from public.kickx_policy)');
   execute definition;
  end if;
 end loop;
end $$;

create function public.kickx_reset_october15_prices(p_expected_parameters jsonb,p_backup jsonb,p_reference jsonb) returns jsonb language plpgsql set search_path='' as $$
declare p public.kickx_policy%rowtype;begin
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('kickx:bsd-import',0));perform public.kickx_economy_lock();
 select * into strict p from public.kickx_policy;
 if p.valuation_rebuild#>>'{priceReset,id}'='launch-20261015-initial50k150k' and p.report_parameters->>'valuationStartMs'='1791990000000'then return '{"unchanged":true}'::jsonb;end if;
 if p.version<>'report-v3' or p.report_parameters is distinct from p_expected_parameters then raise exception 'RESET_POLICY_CHANGED';end if;
 if p_backup->'integrity'is distinct from public.kickx_valuation_integrity()or coalesce(p_backup->>'hash','')!~'^[a-f0-9]{64}$'or coalesce((p_backup->>'bytes')::bigint,0)<=0 or not exists(select 1 from storage.objects where bucket_id='kickx-calculation-archives'and name=p_backup->>'path')then raise exception 'RESET_VERIFIED_BACKUP_REQUIRED';end if;
 if p_reference-'hash'-'scopeAudit'is distinct from p.report_reference-'hash'-'scopeAudit'or p_reference->>'hash'=p.report_reference->>'hash'then raise exception 'RESET_REFERENCE_CHANGED';end if;
 update public.kickx_policy set report_parameters=report_parameters||'{"initialMin":50000,"initialMax":150000,"valuationStartMs":1791990000000}'::jsonb,
 valuation_rebuild=valuation_rebuild||jsonb_build_object('backup',p_backup,'startsAt','2026-10-14T15:00:00Z','priceReset',jsonb_build_object('id','launch-20261015-initial50k150k','resetAt',clock_timestamp(),'backup',p_backup))where id=true;
 return public.kickx_replace_regular_reference(p.report_reference->>'hash',p_reference);
end $$;
revoke all on function public.kickx_reset_october15_prices(jsonb,jsonb,jsonb)from public,anon,authenticated;
grant execute on function public.kickx_reset_october15_prices(jsonb,jsonb,jsonb)to service_role;

-- Reuse validated performance evidence inside the database. Each bounded call
-- retains source-token checks and the standard publisher's withholding rules.
create function public.kickx_replay_cached_prices(p_limit integer default 15) returns jsonb
language plpgsql set search_path='' set jit=off as $$
declare q record;answer jsonb;n integer:=0;held integer:=0;remaining integer;started timestamptz:=clock_timestamp();begin
 if p_limit<1 or p_limit>25 then raise exception 'INVALID_BATCH_SIZE';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('kickx:bsd-import',0));
 perform public.kickx_economy_lock();
 if not exists(select 1 from public.kickx_policy where version='report-v3' and report_parameters->>'valuationStartMs'='1791990000000'
 and report_parameters->>'initialMin'='50000' and report_parameters->>'initialMax'='150000')then raise exception 'RESET_POLICY_REQUIRED';end if;
 for q in select c.player_id,c.revision from public.calculation_queue c
 where c.error_code is null and public.kickx_market_eligible(c.player_id)
 order by c.queued_at,c.player_id limit p_limit for update skip locked loop
  if exists(select 1 from public.kickx_calculation_sources(q.player_id)where not cached)then continue;end if;
  answer:=public.kickx_publish_calculation_delta(null,q.player_id,public.kickx_calculation_token(q.player_id),'[]');
  perform public.kickx_ack_calculation(q.player_id,q.revision,case when answer->>'withheld'='true'then 'CALCULATION_WITHHELD'end);
  n:=n+1;if answer->>'withheld'='true'then held:=held+1;end if;
  exit when clock_timestamp()-started>interval '3 seconds';
 end loop;
 select count(*) into remaining from public.calculation_queue c where error_code is null and public.kickx_market_eligible(c.player_id);
 return jsonb_build_object('processed',n,'withheld',held,'remaining',remaining);
end $$;
revoke all on function public.kickx_replay_cached_prices(integer) from public,anon,authenticated;
grant execute on function public.kickx_replay_cached_prices(integer) to service_role;
notify pgrst,'reload schema';
commit;
