begin;
insert into auth.users(id)values('00000000-0000-0000-0000-000000005300');
insert into public.wallets(user_id,balance,initial_points)values('00000000-0000-0000-0000-000000005300',106066,1300000);
insert into public.wallet_ledger(user_id,kind,delta,balance_after)values
 ('00000000-0000-0000-0000-000000005300','initial',1300000,1300000),
 ('00000000-0000-0000-0000-000000005300','buy',-1246934,53066),
 ('00000000-0000-0000-0000-000000005300','grant',53000,106066);
do $$declare amount bigint;begin
 if(select sum(delta)from public.wallet_ledger where user_id='00000000-0000-0000-0000-000000005300')<>106066 then raise exception 'Grant not included in historical wallet balance';end if;
 if(select initial_points from public.wallets where user_id='00000000-0000-0000-0000-000000005300')<>1300000 then raise exception 'Grant rewrote initial allocation';end if;
 foreach amount in array array[0,-53000]loop
  begin
   insert into public.wallet_ledger(user_id,kind,delta,balance_after)values('00000000-0000-0000-0000-000000005300','grant',amount,106066);
   raise exception 'Nonpositive grant accepted';
  exception when check_violation then null;end;
 end loop;
 begin
  insert into public.wallet_ledger(user_id,kind,delta,balance_after,trade_id)values('00000000-0000-0000-0000-000000005300','grant',53000,106066,'00000000-0000-0000-0000-000000005301');
  raise exception 'Grant mislabeled as a trade';
 exception when check_violation then null;end;
 if has_table_privilege('anon','public.wallet_ledger','insert')or has_table_privilege('authenticated','public.wallet_ledger','insert')then raise exception 'Point grant exposed to client roles';end if;
end $$;
rollback;
