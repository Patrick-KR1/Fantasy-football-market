begin;
create schema if not exists storage;
create table if not exists storage.buckets(id text primary key,public boolean not null default false);
create table if not exists storage.objects(bucket_id text,name text,primary key(bucket_id,name));
insert into storage.buckets(id,public)values('kickx-calculation-archives',false)on conflict do nothing;

insert into public.operation_audit(action,target,detail,created_at)values
 ('calculation.publish','storage-old','{"price":101000,"results":4,"baseline":{"price":100000},"lastStep":{"score":12},"correction":false}',now()-interval '14 days'),
 ('calculation.publish','storage-raced','{"price":102000,"results":5,"baseline":{"price":100000}}',now()-interval '14 days'),
 ('calculation.publish','storage-recent','{"price":103000,"results":6,"baseline":{"price":100000}}',now()),
 ('community.moderate','storage-community','{"baseline":{"reason":"must stay"}}',now()-interval '14 days');

do $$declare batch jsonb;path text:='operation-audit/'||repeat('c',64)||'.json.gz';n integer;begin
 batch:=public.kickx_history_archive_batch('audit',500);
 if not exists(select 1 from jsonb_array_elements(batch) x where x->>'target'='storage-old' and x#>>'{detail,lastStep,score}'='12')then raise exception 'Full audit not exported';end if;
 if exists(select 1 from jsonb_array_elements(batch) x where x->>'target' in('storage-recent','storage-community'))then raise exception 'Recent/non-calculation audit selected';end if;
 begin perform public.kickx_finish_history_archive('audit',path,batch);raise exception 'Unbacked archive accepted';exception when others then if sqlerrm<>'ARCHIVE_OBJECT_REQUIRED'then raise;end if;end;
 insert into storage.objects(bucket_id,name)values('kickx-calculation-archives',path);
 if public.kickx_finish_history_archive('audit',path,'[{"id":"00000000-0000-0000-0000-000000000000","archive_hash":"wrong"}]')<>0 then raise exception 'Wrong hash changed data';end if;
 update public.operation_audit set detail=detail||'{"changed":true}'where target='storage-raced';
 n:=public.kickx_finish_history_archive('audit',path,batch);
 if n<1 then raise exception 'Verified old audit not compacted';end if;
 if not exists(select 1 from public.operation_audit where target='storage-old' and archive_path=path and detail='{"price":101000,"results":4,"correction":false}'::jsonb)then raise exception 'Audit summary changed';end if;
 if not exists(select 1 from public.operation_audit where target='storage-raced' and archive_path is null and detail?'baseline')then raise exception 'Concurrent edit overwritten';end if;
 if public.kickx_finish_history_archive('audit',path,batch)<>0 then raise exception 'Archive acknowledgment not idempotent';end if;
 if not exists(select 1 from kickx_private.history_archives h where h.path='operation-audit/'||repeat('c',64)||'.json.gz' and h.kind='audit')then raise exception 'Archive manifest missing';end if;
 begin perform public.kickx_finish_history_archive('audit','../unsafe','[]');raise exception 'Unsafe path accepted';exception when others then if sqlerrm<>'INVALID_ARCHIVE'then raise;end if;end;
 begin perform public.kickx_finish_history_archive('audit',null,'[]');raise exception 'Null path accepted';exception when others then if sqlerrm<>'INVALID_ARCHIVE'then raise;end if;end;
end $$;

-- Each old day keeps its newest snapshot, separately for each ranking period.
insert into public.ranking_snapshots(id,period,starts_at,ends_at,calculated_at,rows)values
 ('00000000-0000-0000-0000-000000009801','weekly',now()-interval '30 days',now()-interval '23 days',date_trunc('day',now()-interval '20 days')+interval '1 hour','[{"rank":2}]'),
 ('00000000-0000-0000-0000-000000009802','weekly',now()-interval '30 days',now()-interval '23 days',date_trunc('day',now()-interval '20 days')+interval '2 hours','[{"rank":1}]'),
 ('00000000-0000-0000-0000-000000009803','monthly',now()-interval '30 days',now(),date_trunc('day',now()-interval '20 days')+interval '1 hour','[{"rank":3}]'),
 ('00000000-0000-0000-0000-000000009804','weekly',now()-interval '1 day',now()+interval '6 days',now()-interval '2 hours','[{"rank":2}]'),
 ('00000000-0000-0000-0000-000000009805','weekly',now()-interval '1 day',now()+interval '6 days',now()-interval '1 hour','[{"rank":1}]');

do $$declare batch jsonb;path text:='ranking-snapshots/'||repeat('d',64)||'.json.gz';begin
 batch:=public.kickx_history_archive_batch('rankings',500);
 if not exists(select 1 from jsonb_array_elements(batch) x where x->>'id'='00000000-0000-0000-0000-000000009801')then raise exception 'Old duplicate not selected';end if;
 if exists(select 1 from jsonb_array_elements(batch) x where x->>'id' in('00000000-0000-0000-0000-000000009802','00000000-0000-0000-0000-000000009803','00000000-0000-0000-0000-000000009804','00000000-0000-0000-0000-000000009805'))then raise exception 'Latest/cross-period/recent snapshot selected';end if;
 begin perform public.kickx_finish_history_archive('rankings',path,batch);raise exception 'Unbacked ranking archive accepted';exception when others then if sqlerrm<>'ARCHIVE_OBJECT_REQUIRED'then raise;end if;end;
 insert into storage.objects(bucket_id,name)values('kickx-calculation-archives',path);
 perform public.kickx_finish_history_archive('rankings',path,batch);
 if exists(select 1 from public.ranking_snapshots where id='00000000-0000-0000-0000-000000009801')then raise exception 'Backed duplicate remains';end if;
 if (select count(*) from public.ranking_snapshots where id in('00000000-0000-0000-0000-000000009802','00000000-0000-0000-0000-000000009803','00000000-0000-0000-0000-000000009804','00000000-0000-0000-0000-000000009805'))<>4 then raise exception 'Ranking history boundary lost';end if;
 if public.kickx_finish_history_archive('rankings',path,batch)<>0 then raise exception 'Ranking acknowledgment not idempotent';end if;
end $$;

-- Mock pg_cron for local tests only; all objects and rows roll back below.
create schema if not exists cron;
create table if not exists cron.job(jobid bigint primary key,jobname text);
create table if not exists cron.job_run_details(runid bigint primary key,jobid bigint,status text,end_time timestamptz);
insert into cron.job(jobid,jobname)values(9801,'kickx-football-minute'),(9802,'unrelated-job');
insert into cron.job_run_details(runid,jobid,status,end_time)values
 (9811,9801,'succeeded',now()-interval '15 days'),(9812,9801,'succeeded',now()-interval '1 day'),
 (9813,9801,'failed',now()-interval '15 days'),(9814,9801,'failed',now()-interval '31 days'),
 (9815,9802,'succeeded',now()-interval '31 days'),(9816,9801,'running',null);
do $$begin
 if kickx_private.prune_storage_logs(1)<>1 then raise exception 'Pruning not bounded';end if;
 if kickx_private.prune_storage_logs(5000)<>1 then raise exception 'Log retention wrong';end if;
 if (select count(*)from cron.job_run_details where runid in(9812,9813,9815,9816))<>4 then raise exception 'Recent/failed/unrelated/running logs removed';end if;
end $$;

set local role authenticated;
do $$begin
 if has_function_privilege(current_user,'public.kickx_history_archive_batch(text,integer)','execute')
 or has_function_privilege(current_user,'public.kickx_finish_history_archive(text,text,jsonb)','execute')then raise exception 'Archive API exposed';end if;
 begin perform * from kickx_private.history_archives;raise exception 'Archive manifest exposed';exception when insufficient_privilege then null;end;
end $$;
reset role;
rollback;
