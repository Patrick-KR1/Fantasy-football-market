begin;
set local lock_timeout='3s';

-- Picks are immutable after kickoff; settled history is retained beyond the six-card window.
create table kickx_private.match_predictions(
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references auth.users(id) on delete cascade,
 fixture_id text not null references public.fixtures(id),
 team_id text not null references public.teams(id),
 choice text not null check(choice in('win','draw','loss')),
 created_at timestamptz not null default clock_timestamp(),
 updated_at timestamptz not null default clock_timestamp(),
 settled_at timestamptz,
 actual text check(actual in('win','draw','loss')),
 reward bigint,
 unique(user_id,fixture_id),
 check((settled_at is null and actual is null and reward is null) or
 (settled_at is not null and actual is not null and reward is not null and reward=case when choice=actual then 5000 else 1000 end))
);
create index match_predictions_pending on kickx_private.match_predictions(fixture_id,created_at) where settled_at is null;
alter table kickx_private.match_predictions enable row level security;
revoke all on kickx_private.match_predictions from public,anon,authenticated,service_role;

alter table public.wallet_ledger drop constraint wallet_ledger_kind_check;
alter table public.wallet_ledger add constraint wallet_ledger_kind_check check(
 kind in('initial','buy','sell','grant','mission_reward','shop','draw','draw_duplicate','prediction_reward')
 and(kind not in('grant','mission_reward','prediction_reward') or(delta>0 and trade_id is null))
 and(kind not in('shop','draw') or(delta<0 and trade_id is null))
 and(kind<>'draw_duplicate' or(delta>=0 and trade_id is null)));
create or replace function kickx_private.external_delta(u uuid,s timestamptz default null,e timestamptz default null)
returns bigint language sql stable security definer set search_path='' as $$
 select coalesce(sum(delta),0)::bigint from public.wallet_ledger where user_id=u and kind in('mission_reward','shop','prediction_reward')
 and(s is null or created_at>=s) and(e is null or created_at<e) $$;

alter table public.user_notifications add column prediction_actual text,
 add column prediction_choice text,add column prediction_reward bigint;
alter table public.user_notifications drop constraint user_notifications_kind_check,
 drop constraint user_notifications_payload_check;
alter table public.user_notifications add constraint user_notifications_kind_check check(kind in('price','match','comment','reply','prediction')),
 add constraint user_notifications_payload_check check(
 (kind='price' and player_id is not null and price_before is not null and price_after is not null and price_before>0 and price_after>0 and price_before<>price_after)
 or(kind='match' and player_id is not null and fixture_id is not null and starts_at is not null)
 or(kind in('comment','reply') and post_id is not null and comment_id is not null)
 or(kind='prediction' and fixture_id is not null and prediction_actual is not null and prediction_actual in('win','draw','loss')
 and prediction_choice is not null and prediction_choice in('win','draw','loss') and prediction_reward is not null
 and prediction_reward=case when prediction_actual=prediction_choice then 5000 else 1000 end));

create function kickx_private.prediction_result(f public.fixtures,t text) returns text
language sql immutable set search_path='' as $$
 select case when t is null or t not in(f.home_team_id,f.away_team_id) then null when f.status not in('FT','AET','PEN') or f.home_score is null or f.away_score is null then null
 when f.status='PEN' and f.home_score=f.away_score and(f.penalties_home is null or f.penalties_away is null or f.penalties_home=f.penalties_away) then null
 when f.status='PEN' and f.home_score=f.away_score then case when(f.penalties_home>f.penalties_away)=(f.home_team_id=t) then 'win' else 'loss' end
 when f.home_score=f.away_score then 'draw'
 when(f.home_score>f.away_score)=(f.home_team_id=t) then 'win' else 'loss' end $$;

create function kickx_private.prediction_window(t text) returns table(fixture_id text,past boolean)
language sql stable set search_path='' as $$
 (select f.id,true from public.fixtures f where t in(f.home_team_id,f.away_team_id)
 and f.status in('FT','AET','PEN') and f.starts_at<=now() order by f.starts_at desc,f.id desc limit 3)
 union all
 (select f.id,false from public.fixtures f where t in(f.home_team_id,f.away_team_id)
 and f.status not in('FT','AET','PEN','CANC','PST','ABD','AWD','WO') and f.starts_at>now()-interval '18 hours'
 order by f.starts_at,f.id limit 3) $$;

create function public.kickx_predictions() returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare u uuid:=auth.uid();t text;result jsonb;begin
 if u is null then raise exception 'AUTH_REQUIRED';end if;
 select primary_team_id into t from public.profiles where id=u;
 if not found then raise exception 'PROFILE_REQUIRED';end if;
 if t is null then raise exception 'PRIMARY_TEAM_REQUIRED';end if;
 with games as(
 select w.past,f.starts_at,f.id,jsonb_build_object('id',f.id,'homeId',f.home_team_id,'awayId',f.away_team_id,
 'homeName',coalesce(h.name_ko,h.name),'awayName',coalesce(a.name_ko,a.name),'startsAt',f.starts_at,'status',f.status,
 'homeScore',f.home_score,'awayScore',f.away_score,'penaltiesHome',f.penalties_home,'penaltiesAway',f.penalties_away,
 'leagueName',l.name,'canPredict',not w.past and f.starts_at>now() and f.status in('NS','TBD') and p.settled_at is null,
 'choice',p.choice,'actual',coalesce(p.actual,kickx_private.prediction_result(f,t)),
 'reward',p.reward,'settledAt',p.settled_at) item
 from kickx_private.prediction_window(t) w join public.fixtures f on f.id=w.fixture_id
 join public.teams h on h.id=f.home_team_id join public.teams a on a.id=f.away_team_id
 left join public.leagues l on l.id=f.league_id
 left join kickx_private.match_predictions p on p.user_id=u and p.fixture_id=f.id and p.team_id=t)
 select jsonb_build_object('teamId',t,'teamName',(select coalesce(name_ko,name) from public.teams where id=t),
 'serverTime',now(),'past',coalesce((select jsonb_agg(item order by starts_at desc,id desc) from games where past),'[]'::jsonb),
 'upcoming',coalesce((select jsonb_agg(item order by starts_at,id) from games where not past),'[]'::jsonb)) into result;
 return result;
end $$;

create function public.kickx_predict(p_fixture text,p_choice text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare u uuid:=public.kickx_require_active_member();t text;f public.fixtures%rowtype;begin
 if p_choice is null or p_choice not in('win','draw','loss') then raise exception 'INVALID_INPUT';end if;
 perform public.kickx_economy_lock();
 select primary_team_id into t from public.profiles where id=u;
 if t is null then raise exception 'PRIMARY_TEAM_REQUIRED';end if;
 select * into f from public.fixtures where id=p_fixture for share;
 if not found or t not in(f.home_team_id,f.away_team_id) then raise exception 'PREDICTION_UNAVAILABLE';end if;
 if f.starts_at<=clock_timestamp() or f.status not in('NS','TBD') then raise exception 'PREDICTION_CLOSED';end if;
 if not exists(select 1 from kickx_private.prediction_window(t) w where not w.past and w.fixture_id=p_fixture)
 then raise exception 'PREDICTION_UNAVAILABLE';end if;
 perform public.kickx_open_wallet();
 if f.starts_at<=clock_timestamp() then raise exception 'PREDICTION_CLOSED';end if;
 insert into kickx_private.match_predictions(user_id,fixture_id,team_id,choice) values(u,p_fixture,t,p_choice)
 on conflict(user_id,fixture_id) do update set choice=excluded.choice,updated_at=clock_timestamp()
 where match_predictions.settled_at is null and match_predictions.team_id=excluded.team_id;
 if not found then raise exception 'PREDICTION_CLOSED';end if;
 return public.kickx_predictions();
end $$;

-- Bounded, offline settlement. Importers and financial writes use the same lock order.
-- A final result arriving without scores remains pending and is retried automatically.
create function kickx_private.settle_predictions(p_limit integer default 200) returns integer
language plpgsql security definer set search_path='' as $$
declare r record;outcome text;amount bigint;counted integer:=0;begin
 if p_limit is null or p_limit not between 1 and 1000 then raise exception 'INVALID_INPUT';end if;
 perform public.kickx_economy_lock();
 for r in select p.id,p.user_id,p.fixture_id,p.team_id,p.choice,kickx_private.prediction_result(f,p.team_id) outcome
 from kickx_private.match_predictions p join public.fixtures f on f.id=p.fixture_id
 where p.settled_at is null and f.starts_at<=clock_timestamp() and kickx_private.prediction_result(f,p.team_id) is not null
 order by p.created_at,p.id limit p_limit for update of p skip locked loop
  outcome:=r.outcome;amount:=case when r.choice=outcome then 5000 else 1000 end;
  update public.wallets set balance=balance+amount where user_id=r.user_id;
  if not found then raise exception 'PREDICTION_WALLET_MISSING';end if;
  insert into public.wallet_ledger(user_id,kind,delta,balance_after)
  select r.user_id,'prediction_reward',amount,balance from public.wallets where user_id=r.user_id;
  update kickx_private.match_predictions set actual=outcome,reward=amount,settled_at=clock_timestamp() where id=r.id;
  insert into public.asset_snapshots(user_id,value) values(r.user_id,public.kickx_assets(r.user_id));
  insert into public.user_notifications(user_id,kind,fixture_id,source_key,prediction_actual,prediction_choice,prediction_reward)
  values(r.user_id,'prediction',r.fixture_id,'prediction:'||r.id,outcome,r.choice,amount) on conflict(user_id,source_key) do nothing;
  counted:=counted+1;
 end loop;
 return counted;
end $$;

revoke all on function kickx_private.prediction_result(public.fixtures,text),kickx_private.prediction_window(text),
 kickx_private.settle_predictions(integer) from public,anon,authenticated;
grant execute on function kickx_private.settle_predictions(integer) to service_role;
revoke all on function public.kickx_predictions(),public.kickx_predict(text,text) from public,anon;
grant execute on function public.kickx_predictions(),public.kickx_predict(text,text) to authenticated,service_role;

-- Preserve the inbox's privacy, moderation visibility, unread count and pagination.
do $$declare src text;changed text;begin
 src:=pg_get_functiondef('kickx_private.read_notification_feed(bigint,integer,boolean)'::regprocedure);
 changed:=replace(src,$old$n.kind in('price','match')$old$,$new$n.kind in('price','match','prediction')$new$);
 changed:=replace(changed,$old$'postId',n.post_id$old$,$new$'predictionActual',n.prediction_actual,'predictionChoice',n.prediction_choice,'predictionReward',n.prediction_reward,'postId',n.post_id$new$);
 if changed=src or position($needle$'predictionReward',n.prediction_reward$needle$ in changed)=0 then raise exception 'NOTIFICATION_DEFINITION_CHANGED';end if;
 execute changed;
end $$;
do $$begin
 if to_regprocedure('cron.schedule(text,text,text)') is not null then
  execute $q$select cron.schedule('kickx-prediction-rewards','* * * * *','select kickx_private.settle_predictions(200);')$q$;
 end if;
end $$;
notify pgrst,'reload schema';
commit;
