-- Preserve all business data. Full historical audit/ranking rows move only after
-- the worker uploads, downloads and SHA-256-verifies a private gzip archive.
begin;
set local lock_timeout='3s';

alter table public.operation_audit add column archive_path text;
alter table public.operation_audit add column archived_at timestamptz;

create table kickx_private.history_archives (
 path text primary key,
 kind text not null check(kind in ('audit','rankings')),
 compacted_rows integer not null check(compacted_rows>0),
 created_at timestamptz not null default clock_timestamp()
);
alter table kickx_private.history_archives enable row level security;
revoke all on kickx_private.history_archives from public,anon,authenticated;
grant usage on schema kickx_private to service_role;
grant select,insert,update on kickx_private.history_archives to service_role;

create index operation_audit_archive_pending_idx on public.operation_audit(created_at,id)
 where action='calculation.publish' and archive_path is null
 and (detail?'baseline' or detail?'lastStep');

create function public.kickx_history_archive_batch(p_kind text,p_limit integer default 500)
returns jsonb language plpgsql stable set search_path='' as $$
declare answer jsonb;begin
 if p_kind='audit' then
  select coalesce(jsonb_agg(to_jsonb(a)||jsonb_build_object('archive_hash',md5(to_jsonb(a)::text)) order by a.created_at,a.id),'[]') into answer
  from (select * from public.operation_audit
   where action='calculation.publish' and archive_path is null
    and created_at<now()-interval '7 days' and (detail?'baseline' or detail?'lastStep')
   order by created_at,id limit greatest(1,least(coalesce(p_limit,500),500))) a;
 elsif p_kind='rankings' then
  with ranked as materialized (
   select id,row_number() over(partition by period,starts_at,ends_at,(calculated_at at time zone 'Asia/Seoul')::date order by calculated_at desc,id desc) as day_rank
   from public.ranking_snapshots
  ), candidates as (
   select r.* from public.ranking_snapshots r join ranked k using(id)
   where k.day_rank>1 and r.calculated_at<now()-interval '7 days'
   order by r.calculated_at,r.id limit greatest(1,least(coalesce(p_limit,500),500))
  ) select coalesce(jsonb_agg(to_jsonb(r)||jsonb_build_object('archive_hash',md5(to_jsonb(r)::text)) order by r.calculated_at,r.id),'[]') into answer from candidates r;
 else raise exception 'INVALID_ARCHIVE_KIND';end if;
 return answer;
end $$;

create function public.kickx_finish_history_archive(p_kind text,p_path text,p_rows jsonb)
returns integer language plpgsql set search_path='' as $$
declare changed integer;folder text;begin
 folder:=case p_kind when 'audit' then 'operation-audit' when 'rankings' then 'ranking-snapshots' end;
 if folder is null or p_path is null or p_path!~('^'||folder||'/[a-f0-9]{64}[.]json[.]gz$')
  or jsonb_typeof(p_rows) is distinct from 'array' or jsonb_array_length(p_rows)>500 then raise exception 'INVALID_ARCHIVE';end if;
 if not public.kickx_archive_object_exists(p_path) then raise exception 'ARCHIVE_OBJECT_REQUIRED';end if;
 if p_kind='audit' then
  -- Keep the time, actor, action, target, price, result count and correction flag.
  -- The full original baseline/lastStep remain recoverable from archive_path.
  update public.operation_audit a set detail=a.detail-'baseline'-'lastStep',archive_path=p_path,archived_at=clock_timestamp()
  from jsonb_to_recordset(p_rows) x(id uuid,archive_hash text)
  where a.id=x.id and a.action='calculation.publish' and a.archive_path is null
   and a.created_at<now()-interval '7 days' and (a.detail?'baseline' or a.detail?'lastStep')
   and md5(to_jsonb(a)::text)=x.archive_hash;
 else
  -- Recheck both content and a surviving newer snapshot of this SAME day and
  -- ranking period. The latest daily/weekly/monthly results cannot be removed.
  delete from public.ranking_snapshots r using jsonb_to_recordset(p_rows) x(id uuid,archive_hash text)
  where r.id=x.id and r.calculated_at<now()-interval '7 days' and md5(to_jsonb(r)::text)=x.archive_hash
   and exists(select 1 from public.ranking_snapshots n where n.period=r.period and n.starts_at=r.starts_at and n.ends_at=r.ends_at
    and (n.calculated_at at time zone 'Asia/Seoul')::date=(r.calculated_at at time zone 'Asia/Seoul')::date
    and (n.calculated_at,n.id)>(r.calculated_at,r.id));
 end if;
 get diagnostics changed=row_count;
 if changed>0 then
  insert into kickx_private.history_archives(path,kind,compacted_rows) values(p_path,p_kind,changed)
  on conflict(path)do update set compacted_rows=history_archives.compacted_rows+excluded.compacted_rows;
 end if;
 return changed;
end $$;
revoke all on function public.kickx_history_archive_batch(text,integer),public.kickx_finish_history_archive(text,text,jsonb) from public,anon,authenticated;
grant execute on function public.kickx_history_archive_batch(text,integer),public.kickx_finish_history_archive(text,text,jsonb) to service_role;

-- Execution logs are operational telemetry, not transactions or reward records.
-- Bound each cleanup and retain failed runs longer than successful runs.
create function kickx_private.prune_storage_logs(p_limit integer default 5000)
returns integer language plpgsql set search_path='' as $$
declare removed integer:=0;begin
 if to_regclass('cron.job_run_details') is null then return 0;end if;
 execute $q$delete from cron.job_run_details where runid in(
  select d.runid from cron.job_run_details d join cron.job j using(jobid)
  where j.jobname in ('kickx-football-minute','kickx-notifications','kickx-storage-maintenance')
   and d.end_time is not null and ((d.status='succeeded' and d.end_time<now()-interval '14 days')
    or (d.status='failed' and d.end_time<now()-interval '30 days'))
  order by d.end_time,d.runid limit greatest(1,least(coalesce($1,5000),5000)))$q$ using p_limit;
 get diagnostics removed=row_count;return removed;
end $$;
revoke all on function kickx_private.prune_storage_logs(integer) from public,anon,authenticated,service_role;
do $$begin
 if to_regprocedure('cron.schedule(text,text,text)') is not null then
  execute $q$select cron.schedule('kickx-storage-maintenance','17 * * * *','select kickx_private.prune_storage_logs();')$q$;
 end if;
end $$;

-- Reuse dead space earlier instead of allowing repeated source/result upserts
-- and archive compactions to accumulate until the default 20% threshold.
alter table public.football_match_stats set(autovacuum_vacuum_scale_factor=.03,autovacuum_vacuum_threshold=200,toast.autovacuum_vacuum_scale_factor=.03);
alter table public.calculation_revisions set(autovacuum_vacuum_scale_factor=.03,autovacuum_vacuum_threshold=200,toast.autovacuum_vacuum_scale_factor=.03);
alter table public.performance_results set(autovacuum_vacuum_scale_factor=.03,autovacuum_vacuum_threshold=200,toast.autovacuum_vacuum_scale_factor=.03);
alter table public.ranking_snapshots set(autovacuum_vacuum_scale_factor=.03,autovacuum_vacuum_threshold=50,toast.autovacuum_vacuum_scale_factor=.03);
notify pgrst,'reload schema';
commit;
