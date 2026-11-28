-- Disposable database only: fixtures, identities and rewards roll back.
begin;
insert into auth.users(id) values('00000000-0000-0000-0000-000000009001'),('00000000-0000-0000-0000-000000009002'),('00000000-0000-0000-0000-000000009003');
insert into public.leagues(id,name) values('bsd-1','Prediction League') on conflict do nothing;
insert into public.teams(id,name,league_id) values('predict-main','내 구단','bsd-1'),('predict-other','상대 구단','bsd-1'),('predict-third','다른 구단','bsd-1');
insert into public.profiles(id,nickname,primary_team_id,primary_confirmed_at,team_ids)
values('00000000-0000-0000-0000-000000009001','예측 회원1','predict-main',now(),array['predict-main']),
('00000000-0000-0000-0000-000000009002','예측 회원2','predict-main',now(),array['predict-main']),
('00000000-0000-0000-0000-000000009003','미설정 회원',null,null,array[]::text[]);
insert into public.fixtures(id,home_team_id,away_team_id,league_id,starts_at,status,home_score,away_score)
select 'predict-p'||i,'predict-main','predict-other','bsd-1',now()-i*interval '1 day','FT',2,1 from generate_series(1,4)i;
insert into public.fixtures(id,home_team_id,away_team_id,league_id,starts_at,status)
select 'predict-u'||i,case when i=1 then 'predict-other' else 'predict-main' end,
case when i=1 then 'predict-main' else 'predict-other' end,'bsd-1',now()+i*interval '1 day','NS' from generate_series(1,6)i;
insert into public.fixtures(id,home_team_id,away_team_id,league_id,starts_at,status)
values('predict-unrelated','predict-other','predict-third','bsd-1',now()+interval '1 hour','NS');
create function pg_temp.pred_assert(ok boolean,msg text) returns void language plpgsql as $$begin if ok is distinct from true then raise exception '%',msg;end if;end $$;
create function pg_temp.pred_error(command text,expected text) returns void language plpgsql as $$begin
 begin execute command;exception when others then if sqlerrm=expected or sqlstate=expected then return;else raise;end if;end;
 raise exception 'Expected % from %',expected,command;end $$;
set local role anon;
select pg_temp.pred_error('select public.kickx_predictions()','42501');
reset role;
set local role authenticated;
set local request.jwt.claim.sub='';
select pg_temp.pred_error('select public.kickx_predictions()','AUTH_REQUIRED');
set local request.jwt.claim.sub='00000000-0000-0000-0000-000000009003';
select pg_temp.pred_error('select public.kickx_predictions()','PRIMARY_TEAM_REQUIRED');
select pg_temp.pred_error($q$select public.kickx_predict('predict-u1','win')$q$,'PRIMARY_TEAM_REQUIRED');
set local request.jwt.claim.sub='00000000-0000-0000-0000-000000009001';
select pg_temp.pred_assert(public.kickx_predictions()#>>'{past,0,id}'='predict-p1','Past must be newest first');
select pg_temp.pred_assert(jsonb_array_length(public.kickx_predictions()->'past')=3,'Exactly three past matches');
select pg_temp.pred_assert(public.kickx_predictions()#>>'{upcoming,2,id}'='predict-u3','Next three must be soonest first');
select pg_temp.pred_error($q$select public.kickx_predict('predict-u1','other')$q$,'INVALID_INPUT');
select pg_temp.pred_error($q$select public.kickx_predict('predict-u4','win')$q$,'PREDICTION_UNAVAILABLE');
select pg_temp.pred_error($q$select public.kickx_predict('predict-unrelated','win')$q$,'PREDICTION_UNAVAILABLE');
select pg_temp.pred_error($q$select public.kickx_predict('predict-p1','win')$q$,'PREDICTION_CLOSED');
select pg_temp.pred_error('select * from kickx_private.match_predictions','42501');
select pg_temp.pred_error('select kickx_private.settle_predictions()','42501');
select public.kickx_predict('predict-u1','loss');
select public.kickx_predict('predict-u1','win');
select public.kickx_predict('predict-u2','draw');
select public.kickx_predict('predict-u3','loss');
select pg_temp.pred_assert(public.kickx_predictions()#>>'{upcoming,0,choice}'='win','Latest choice must replace earlier pick');
select pg_temp.pred_assert((select balance from public.wallets)=1300000,'Predictions must be free');
set local request.jwt.claim.sub='00000000-0000-0000-0000-000000009002';
select pg_temp.pred_assert(public.kickx_predictions()#>'{upcoming,0,choice}'='null'::jsonb,'Never expose another user pick');
select public.kickx_predict('predict-u1','loss');
reset role;
update public.fixtures set starts_at=now()-interval '3 hours'+right(id,1)::int*interval '1 minute',status='FT',
home_score=case when id='predict-u2' then 1 else 0 end,away_score=case when id='predict-u1' then 2 else 1 end
where id in('predict-u1','predict-u2','predict-u3');
select pg_temp.pred_assert(kickx_private.settle_predictions(2)=2,'Settlement must honor batch bound');
select pg_temp.pred_assert(kickx_private.settle_predictions(2)=2,'Remaining picks must settle');
select pg_temp.pred_assert(kickx_private.settle_predictions()=0,'Settlement must be idempotent');
select pg_temp.pred_assert((select balance from public.wallets where user_id='00000000-0000-0000-0000-000000009001')=1315000,'Three correct results must pay 15000');
select pg_temp.pred_assert((select balance from public.wallets where user_id='00000000-0000-0000-0000-000000009002')=1301000,'Incorrect prediction must pay 1000');
select pg_temp.pred_assert((select count(*) from public.wallet_ledger where kind='prediction_reward')=4,'Exactly one ledger entry per pick');
select pg_temp.pred_assert((select count(*) from public.user_notifications where kind='prediction')=4,'Exactly one result notification per pick');
set local role authenticated;
set local request.jwt.claim.sub='00000000-0000-0000-0000-000000009001';
select pg_temp.pred_assert(public.kickx_predictions()#>>'{past,0,id}'='predict-u3','Finished fixture must enter past window');
select pg_temp.pred_assert(public.kickx_predictions()#>>'{past,2,id}'='predict-u1','Oldest previous fixture must leave visible window');
select pg_temp.pred_assert(public.kickx_predictions()#>>'{upcoming,0,id}'='predict-u4','Next fixture must roll into upcoming window');
select pg_temp.pred_assert((public.kickx_member_data()->>'returnRate')::numeric=0,'Prediction reward must not inflate investment return');
select pg_temp.pred_assert(public.kickx_notification_summary()->>'hasUnread'='true','Prediction notifications must count as unread');
select pg_temp.pred_assert(jsonb_array_length(public.kickx_notifications(null,2)->'items')=2 and public.kickx_notifications(null,2)->>'hasMore'='true','Prediction inbox pagination must work');
select pg_temp.pred_assert(public.kickx_notifications()#>>'{items,0,predictionReward}'='5000','Inbox must include reward');
select pg_temp.pred_error($q$select public.kickx_predict('predict-u1','loss')$q$,'PREDICTION_CLOSED');
select public.kickx_predict('predict-u4','win');
select public.kickx_predict('predict-u5','win');
reset role;
update public.fixtures set status='CANC' where id='predict-u4';
update public.fixtures set starts_at=now()-interval '1 hour',status='FT' where id='predict-u5';
select pg_temp.pred_assert(kickx_private.settle_predictions()=0,'Cancelled or scoreless games must not pay');
update public.fixtures set home_score=3,away_score=0 where id='predict-u5';
select pg_temp.pred_assert(kickx_private.settle_predictions()=1,'Late scores must settle without a user visit');
update public.fixtures set starts_at=now()-interval '1 second' where id='predict-u6';
set local role authenticated;
select pg_temp.pred_error($q$select public.kickx_predict('predict-u6','win')$q$,'PREDICTION_CLOSED');
reset role;
-- A corrected final score cannot issue a second payout.
update public.fixtures set home_score=0,away_score=3 where id='predict-u5';
select pg_temp.pred_assert(kickx_private.settle_predictions()=0,'Result corrections must never double-pay');
select pg_temp.pred_assert((select actual='win' and reward=5000 from kickx_private.match_predictions where fixture_id='predict-u5'),'Settled reward audit must remain intact');
-- Penalty outcomes use the winning club, not a misleading draw on the scoreboard.
update public.fixtures set status='PEN',home_score=1,away_score=1,penalties_home=4,penalties_away=3 where id='predict-p1';
select pg_temp.pred_assert((select kickx_private.prediction_result(f,'predict-main')='win' from public.fixtures f where id='predict-p1'),'Penalty winner must win');
update public.fixtures set penalties_away=null where id='predict-p1';
select pg_temp.pred_assert((select kickx_private.prediction_result(f,'predict-main') is null from public.fixtures f where id='predict-p1'),'Missing penalty scores must await data');
rollback;
