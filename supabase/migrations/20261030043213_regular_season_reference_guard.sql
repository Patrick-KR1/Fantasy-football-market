-- The five league IDs can also contain relegation playoffs. Verify regular-season scope before any price reset.
create or replace function public.kickx_activate_report_policy() returns integer language plpgsql set search_path='' as $$
declare p public.kickx_policy%rowtype;k text;r record;n integer:=0;begin
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('kickx:bsd-import',0));perform public.kickx_economy_lock();
 select * into strict p from public.kickx_policy;
 if p.version='report-v3' and p.valuation_rebuild->>'status'='active' then return 0;end if;
 if p.valuation_rebuild->>'status' is distinct from 'validated' then raise exception 'VALUATION_AUDIT_REQUIRED';end if;
 if not exists(select 1 from storage.objects o where o.bucket_id='kickx-calculation-archives' and o.name=p.valuation_rebuild#>>'{backup,path}') then raise exception 'VALUATION_BACKUP_REQUIRED';end if;
 if p.report_reference->>'status' is distinct from 'ready' or jsonb_array_length(p.report_reference->'archives')=0
 or (p.report_reference->>'completed')::integer<>(p.report_reference->>'fixtureCount')::integer then raise exception 'REFERENCE_NOT_READY';end if;
 foreach k in array array['GK','DF','MF','FW'] loop
  if coalesce(jsonb_array_length(p.report_reference->'groups'->k->'baselines'),0)=0 then raise exception 'REFERENCE_NOT_READY';end if;
 end loop;
 if exists(select 1 from jsonb_array_elements(p.report_reference->'archives') a where not exists(
  select 1 from storage.objects o where o.bucket_id='kickx-calculation-archives' and o.name=a->>'path')) then raise exception 'REFERENCE_ARCHIVE_MISSING';end if;
 if p.report_reference->>'regularSeasonScopeVerified' is distinct from 'true' then raise exception 'REGULAR_SEASON_SCOPE_REQUIRED';end if;
 update public.kickx_policy set version='report-v3',club_competitions_enabled=false,pricing_reference_at=timestamptz '2026-09-30T15:00:00Z',valuation_rebuild=valuation_rebuild||jsonb_build_object('status','active','activatedAt',clock_timestamp()),pricing_reference_season=(report_reference->>'season')::integer+1 where id=true;
 perform public.kickx_report_refresh_summaries();
 delete from public.realtime_fixture_tasks t using public.fixtures f where f.id=t.fixture_id and f.league_id not in('bsd-1','bsd-3','bsd-4','bsd-5','bsd-6');
 -- Reset derived market prices to the audited initial basis. Never alter trades, wallet balances or acquisition costs.
 update public.player_market_snapshots s set price=(b.detail->>'price')::numeric,performance=null,change_percent=0,pricing_status='pending',performance_rule_version=null,pricing_rule_version='report-v3',updated_at=clock_timestamp()
 from (select z.id,public.kickx_report_baseline(z.id,z.position,p.report_reference,p.report_parameters) detail from public.players z where public.kickx_market_eligible(z.id)) b where s.id=b.id and b.detail is not null;
 for r in select id from public.players where public.kickx_market_eligible(id) loop perform public.kickx_queue_player(r.id);n:=n+1;end loop;
 insert into public.operation_audit(action,detail) values('policy.report-v3',jsonb_build_object('referenceHash',p.report_reference->>'hash','parameters',p.report_parameters));
 return n;
end $$;
