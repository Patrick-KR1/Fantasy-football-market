begin;
insert into auth.users(id)values('50000000-0000-4000-8000-000000000001'),('50000000-0000-4000-8000-000000000002');
insert into public.leagues(id,name)values('bsd-1','Sample test')on conflict do nothing;
insert into public.teams(id,name,league_id)values('sample-test-team','Team','bsd-1');
insert into public.profiles(id,nickname,team_id,sample_batch)values
 ('50000000-0000-4000-8000-000000000001','주말엔축구','sample-test-team','kickx-demo-20261030'),
 ('50000000-0000-4000-8000-000000000002','Regular account','sample-test-team',null);
insert into public.players(id,name,provider,team_id,position)values('sample-test-a','A','bsd','sample-test-team','FW'),('sample-test-b','B','bsd','sample-test-team','DF');
insert into public.player_market_snapshots(id,price,pricing_status,pricing_rule_version)values('sample-test-a',100000,'ready','report-v3'),('sample-test-b',100000,'ready','report-v3');
update public.kickx_policy set version='report-v3';
do $$begin
 if has_function_privilege('authenticated','public.kickx_sample_action(uuid,text,jsonb)','execute')or has_function_privilege('anon','public.kickx_sample_action(uuid,text,jsonb)','execute')then raise exception 'Sample actor exposed';end if;
 if has_column_privilege('authenticated','public.profiles','sample_batch','update')or has_column_privilege('authenticated','public.profiles','sample_batch','insert')then raise exception 'Sample marker user-editable';end if;
 begin perform public.kickx_sample_action('50000000-0000-4000-8000-000000000002','open','{}');raise exception 'Real account accepted';
 exception when others then if sqlerrm<>'SAMPLE_ACCOUNT_REQUIRED'then raise;end if;end;
end $$;
set local role service_role;
select public.kickx_sample_action('50000000-0000-4000-8000-000000000001','open');
do $$declare input jsonb;result jsonb;balance bigint;begin
 input:='{"trades":[{"playerId":"sample-test-a","side":"buy","requestId":"51000000-0000-4000-8000-000000000001"},{"playerId":"sample-test-a","side":"sell","requestId":"51000000-0000-4000-8000-000000000002"},{"playerId":"sample-test-b","side":"buy","requestId":"51000000-0000-4000-8000-000000000003"}]}';
 result:=public.kickx_sample_action('50000000-0000-4000-8000-000000000001','portfolio',input);
 if jsonb_array_length(result->'trades')<>3 then raise exception 'Trades missing';end if;
 select w.balance into balance from public.wallets w where user_id='50000000-0000-4000-8000-000000000001';
 if balance<>1198000 or(select count(*)from public.holdings where user_id='50000000-0000-4000-8000-000000000001')<>1 then raise exception 'Wallet/holdings mismatch';end if;
 if (select sum(delta)from public.wallet_ledger where user_id='50000000-0000-4000-8000-000000000001')<>balance then raise exception 'Ledger mismatch';end if;
 perform public.kickx_sample_action('50000000-0000-4000-8000-000000000001','portfolio',input);
 if (select count(*)from public.trades where user_id='50000000-0000-4000-8000-000000000001')<>3 then raise exception 'Duplicate trades';end if;
 perform public.kickx_sample_action('50000000-0000-4000-8000-000000000001','post',jsonb_build_object('scope','player','target','sample-test-b','title','Sample purchase','body','A marked sample purchase using its own receipt.','requestId','52000000-0000-4000-8000-000000000001','transaction',result#>>'{trades,2,id}'));
end $$;
rollback;
