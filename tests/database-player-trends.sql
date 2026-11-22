begin;
insert into public.leagues(id,name) values('bsd-1','Trend League') on conflict do nothing;
insert into public.teams(id,name,league_id) values('trend-club','Trend Club','bsd-1');
insert into public.players(id,name,provider,position,team_id) values('trend-a','Trend A','bsd','FW','trend-club'),('trend-b','Trend B','bsd','MF','trend-club'),('trend-c','Trend C','bsd','DF','trend-club');
insert into public.price_history(player_id,value,recorded_at,rule_version) values
 ('trend-a',100000,now()-interval '40 days','prototype-v1'),
 ('trend-a',101000,now()-interval '10 days','prototype-v1'),
 ('trend-a',102000,date_trunc('day',now()-interval '5 days')+interval '3 hours','prototype-v1'),
 ('trend-a',103000,date_trunc('day',now()-interval '5 days')+interval '4 hours','prototype-v1'),
 ('trend-b',50000,now()-interval '45 days','prototype-v1');
set local role anon;
do $$declare t jsonb:=public.kickx_player_trends(array['trend-a','trend-b','trend-c','trend-a']);begin
 -- anchor before the window, then one value per Korean day (the last of that day)
 if jsonb_array_length(t->'trend-a')<>3 or (t#>>'{trend-a,0,value}')::numeric<>100000 or (t#>>'{trend-a,2,value}')::numeric<>103000 then raise exception 'Trend series wrong: %',t->'trend-a';end if;
 if jsonb_array_length(t->'trend-b')<>1 or (t#>>'{trend-b,0,value}')::numeric<>50000 then raise exception 'Anchor-only trend wrong: %',t->'trend-b';end if;
 if t ? 'trend-c' then raise exception 'Player without history returned a series';end if;
end $$;
reset role;
rollback;
