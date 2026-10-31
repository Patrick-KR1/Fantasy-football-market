-- A player's market snapshot covers every match. Its pending flag must not
-- turn an otherwise scored, unrelated fixture back into calculation pending.
-- This badge describes fixture-local scoring, not the player's price release.
begin;
set local lock_timeout='3s';
create or replace function public.kickx_fixture_reflection(p_fixture text,p_status text)
returns text language plpgsql stable strict security invoker set search_path='' as $$
begin
 if p_status not in('FT','AET','PEN') then return null;end if;
 -- Use the existing fixture/status index and stop after the first match.
 if exists(select 1 from public.performance_results r where r.fixture_id=p_fixture and r.status='blocked') then
  if exists(select 1 from public.performance_results r where r.fixture_id=p_fixture and r.status in('ready','provisional','not-played'))
   then return 'partial';else return 'withheld';end if;
 end if;
 if exists(select 1 from public.performance_results r where r.fixture_id=p_fixture and r.status in('ready','provisional','not-played'))then return 'reflected';end if;
 return 'pending';
end $$;
revoke all on function public.kickx_fixture_reflection(text,text) from public;
grant execute on function public.kickx_fixture_reflection(text,text) to anon,authenticated,service_role;
commit;
