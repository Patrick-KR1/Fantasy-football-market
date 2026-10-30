-- Seed markers do not create a second account or ledger model. Only the service
-- role can label sample profiles; browser clients retain their existing grants.
begin;
alter table public.profiles add column sample_batch text check(sample_batch is null or char_length(sample_batch)<=64);
revoke insert(sample_batch),update(sample_batch) on public.profiles from anon,authenticated;

create function public.kickx_sample_action(p_user uuid,p_action text,p_input jsonb default '{}')returns jsonb
language plpgsql set search_path='' as $$
declare e jsonb;q jsonb;t jsonb;existing public.trades%rowtype;done jsonb:='[]';skipped jsonb:='[]';begin
 if not exists(select 1 from public.profiles where id=p_user and sample_batch='kickx-demo-20261030'and nickname like '%_샘플')
 or exists(select 1 from public.user_roles where user_id=p_user and role='admin')then raise exception 'SAMPLE_ACCOUNT_REQUIRED';end if;
 perform set_config('request.jwt.claim.sub',p_user::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',p_user,'role','authenticated')::text,true);
 if p_action='open'then
  insert into public.user_roles(user_id,role)values(p_user,'member')on conflict do nothing;
  return public.kickx_open_wallet();
 elsif p_action='portfolio'then
  if jsonb_typeof(p_input->'trades')is distinct from 'array'or jsonb_array_length(p_input->'trades')>20 then raise exception 'INVALID_SAMPLE_PLAN';end if;
  for e in select value from jsonb_array_elements(p_input->'trades')loop
   select *into existing from public.trades where user_id=p_user and request_id=(e->>'requestId')::uuid;
   if found then
    if existing.player_id is distinct from e->>'playerId'or existing.side is distinct from e->>'side'then raise exception 'REQUEST_REUSED';end if;
    done:=done||jsonb_build_array(to_jsonb(existing));continue;
   end if;
   begin
    q:=public.kickx_quote(e->>'playerId',e->>'side');
    t:=public.kickx_trade((q->>'id')::uuid,(e->>'requestId')::uuid);
    done:=done||jsonb_build_array(t);
   exception when others then
    if sqlerrm not in('MATCH_TRADING_LOCKED','PRICE_RECALCULATING','PRICE_CHANGED','INSUFFICIENT_POINTS','ALREADY_OWNED','NOT_OWNED','TRADING_PAUSED')then raise;end if;
    skipped:=skipped||jsonb_build_array(jsonb_build_object('playerId',e->>'playerId','side',e->>'side','reason',sqlerrm));
   end;
  end loop;
  return jsonb_build_object('trades',done,'skipped',skipped);
 elsif p_action='post'then return public.kickx_community_write('createPost',p_input);
 elsif p_action='comment'then return public.kickx_community_write('comment',p_input);
 end if;
 raise exception 'INVALID_SAMPLE_ACTION';
end $$;
revoke all on function public.kickx_sample_action(uuid,text,jsonb)from public,anon,authenticated;
grant execute on function public.kickx_sample_action(uuid,text,jsonb)to service_role;
grant execute on function public.kickx_quote(text,text),public.kickx_trade(uuid,uuid),public.kickx_open_wallet(),public.kickx_community_write(text,jsonb)to service_role;
notify pgrst,'reload schema';
commit;
