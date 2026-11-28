-- Fingerprint only the requested primary-key rows. A generic UPDATE join may
-- choose to hash the entire audit table before joining the small JSON batch.
begin;
set local lock_timeout='3s';
create or replace function public.kickx_finish_history_archive(p_kind text,p_path text,p_rows jsonb)
returns integer language plpgsql set search_path='' set jit=off as $$
declare changed integer:=0;folder text;item record;
 audit_row public.operation_audit%rowtype;rank_row public.ranking_snapshots%rowtype;
begin
 folder:=case p_kind when 'audit' then 'operation-audit' when 'rankings' then 'ranking-snapshots' end;
 if folder is null or p_path is null or p_path!~('^'||folder||'/[a-f0-9]{64}[.]json[.]gz$')
  or jsonb_typeof(p_rows) is distinct from 'array' or jsonb_array_length(p_rows)>500 then raise exception 'INVALID_ARCHIVE';end if;
 if not public.kickx_archive_object_exists(p_path) then raise exception 'ARCHIVE_OBJECT_REQUIRED';end if;
 -- A stable lock order also makes overlapping workers safe. Busy rows stay
 -- intact and are reconsidered in a later batch, without blocking the app.
 for item in select * from jsonb_to_recordset(p_rows) x(id uuid,archive_hash text) order by x.id loop
  if p_kind='audit' then
   select a.* into audit_row from public.operation_audit a where a.id=item.id for update of a skip locked;
   if not found then continue;end if;
   if audit_row.action='calculation.publish' and audit_row.archive_path is null
    and audit_row.created_at<now()-interval '7 days' and (audit_row.detail?'baseline' or audit_row.detail?'lastStep')
    and md5(to_jsonb(audit_row)::text)=item.archive_hash then
    update public.operation_audit set detail=detail-'baseline'-'lastStep',archive_path=p_path,archived_at=clock_timestamp() where id=audit_row.id;
    changed:=changed+1;
   end if;
  else
   select r.* into rank_row from public.ranking_snapshots r where r.id=item.id for update of r skip locked;
   if not found then continue;end if;
   if rank_row.calculated_at<now()-interval '7 days' and md5(to_jsonb(rank_row)::text)=item.archive_hash
    and exists(select 1 from public.ranking_snapshots n where n.period=rank_row.period
     and n.starts_at=rank_row.starts_at and n.ends_at=rank_row.ends_at
     and n.calculated_at>=(((rank_row.calculated_at at time zone 'Asia/Seoul')::date)::timestamp at time zone 'Asia/Seoul')
     and n.calculated_at<((((rank_row.calculated_at at time zone 'Asia/Seoul')::date)+1)::timestamp at time zone 'Asia/Seoul')
     and (n.calculated_at,n.id)>(rank_row.calculated_at,rank_row.id)) then
    delete from public.ranking_snapshots where id=rank_row.id;
    changed:=changed+1;
   end if;
  end if;
 end loop;
 if changed>0 then
  insert into kickx_private.history_archives(path,kind,compacted_rows) values(p_path,p_kind,changed)
  on conflict(path)do update set compacted_rows=history_archives.compacted_rows+excluded.compacted_rows;
 end if;
 return changed;
end $$;
revoke all on function public.kickx_finish_history_archive(text,text,jsonb) from public,anon,authenticated;
grant execute on function public.kickx_finish_history_archive(text,text,jsonb) to service_role;
notify pgrst,'reload schema';
commit;
