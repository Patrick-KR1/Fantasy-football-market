-- Members with a confirmed primary club may author posts in any of their supported clubs
-- (previously the primary club only). Comment and poll participation rules are unchanged.
create or replace function public.kickx_can_write_lounge(u uuid,s text,t text) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.profiles p where p.id=u and (s='player' or s='club' and p.primary_team_id is not null and t=any(p.team_ids)))
$$;
revoke all on function public.kickx_can_write_lounge(uuid,text,text) from public,anon,authenticated;
grant execute on function public.kickx_can_write_lounge(uuid,text,text) to service_role;
