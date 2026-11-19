-- Missions, cosmetics and uniform player draws. All money changes share the trade lock.
begin;
set local lock_timeout='10s';
select public.kickx_economy_lock();

create table kickx_private.mission_days(
 user_id uuid not null references auth.users(id) on delete cascade,day date not null,
 choices text[] not null check(cardinality(choices)=2),cleared_at timestamptz,claimed_at timestamptz,
 primary key(user_id,day));
create table kickx_private.mission_events(
 user_id uuid not null references auth.users(id) on delete cascade,day date not null,
 kind text not null check(kind in('ai_report','player_post','club_post','fixtures','watch','price','comment','sell')),
 target text not null,occurred_at timestamptz not null default clock_timestamp(),
 primary key(user_id,day,kind,target));
create table kickx_private.attendance(
 user_id uuid not null references auth.users(id) on delete cascade,day date not null,
 recovered boolean not null default false,created_at timestamptz not null default clock_timestamp(),primary key(user_id,day));
create table kickx_private.weekly_claims(
 user_id uuid not null references auth.users(id) on delete cascade,week date not null,
 international boolean not null,claimed_at timestamptz not null default clock_timestamp(),primary key(user_id,week));
create table kickx_private.roster_history(
 id bigint generated always as identity primary key,user_id uuid not null references auth.users(id) on delete cascade,
 player_id text not null references public.players(id),owned boolean not null,starter boolean not null,
 recorded_at timestamptz not null default clock_timestamp());
create index mission_roster_history_lookup on kickx_private.roster_history(user_id,player_id,recorded_at desc,id desc);
create index mission_roster_history_player on kickx_private.roster_history(player_id,user_id);
insert into kickx_private.roster_history(user_id,player_id,owned,starter)
 select user_id,player_id,true,bench_started_at is null from public.holdings;

create table kickx_private.shop_items(
 id text primary key,category text not null check(category in('nameplate','frame','pitch','ticket')),
 name text not null,description text not null,price bigint not null check(price>0),theme text not null,sort_order integer not null);
insert into kickx_private.shop_items values
 ('nameplate-aurora','nameplate','오로라 드라이브','빛의 궤적이 흐르는 시안·핑크 네임태그',12000,'aurora',1),
 ('nameplate-arcane','nameplate','아케인 크라운','보랏빛 룬과 수정 문양의 네임태그',18000,'arcane',2),
 ('nameplate-circuit','nameplate','제로 서킷','전류가 흐르는 청록 회로 네임태그',18000,'circuit',3),
 ('nameplate-inferno','nameplate','인페르노','붉은 금속과 불꽃의 네임태그',25000,'inferno',4),
 ('frame-laurel','frame','승리의 월계관','선수 아이콘을 감싸는 황금빛 월계 테두리',8000,'laurel',5),
 ('frame-circuit','frame','네온 코어','청록빛 이중 회로 테두리',12000,'circuit',6),
 ('frame-arcane','frame','룬 크리스털','보랏빛 수정 테두리',15000,'arcane',7),
 ('pitch-myth','pitch','올림포스','대리석과 황금 문양의 신화 경기장',30000,'myth',8),
 ('pitch-engineering','pitch','메카 그리드','격자와 회로가 교차하는 공학 경기장',30000,'engineering',9),
 ('pitch-christmas','pitch','윈터 빌리지','눈과 작은 불빛의 크리스마스 경기장',30000,'christmas',10),
 ('pitch-volcano','pitch','마그마 아레나','검은 암석 사이로 용암이 흐르는 경기장',30000,'volcano',11),
 ('pitch-cosmos','pitch','스타라이트','별빛과 성운의 우주 경기장',30000,'cosmos',12),
 ('attendance-ticket','ticket','출석 복구권','이번 주의 지난 결석일 1일 복구 · 일일 보상 소급 없음',2000,'ticket',13);
create table kickx_private.shop_purchases(
 id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id) on delete cascade,
 item_id text not null references kickx_private.shop_items(id),price bigint not null,request_id uuid not null,
 created_at timestamptz not null default clock_timestamp(),unique(user_id,request_id));
create index shop_purchase_user on kickx_private.shop_purchases(user_id,created_at desc);
create table kickx_private.cosmetic_inventory(
 user_id uuid not null references auth.users(id) on delete cascade,item_id text not null references kickx_private.shop_items(id),
 quantity integer not null check(quantity>=0),primary key(user_id,item_id));
create table kickx_private.cosmetic_loadouts(
 user_id uuid primary key references auth.users(id) on delete cascade,nameplate text references kickx_private.shop_items(id),
 frame text references kickx_private.shop_items(id),pitch text references kickx_private.shop_items(id),
 faces boolean not null default false);
create table kickx_private.player_draws(
 id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id) on delete cascade,
 day date not null,player_id text not null references public.players(id),player_name text not null,
 price_at_draw bigint not null check(price_at_draw>0),pool_size integer not null check(pool_size>0),
 request_id uuid not null,status text not null default 'pending' check(status in('pending','placed','duplicate')),
 compensation bigint,bench_player text,created_at timestamptz not null default clock_timestamp(),settled_at timestamptz,
 unique(user_id,day),unique(user_id,request_id));
create index player_draw_pending on kickx_private.player_draws(user_id) where status='pending';
-- Private schema and RLS both protect progress, ownership, balances and random results.
do $$declare t text;begin
 foreach t in array array['mission_days','mission_events','attendance','weekly_claims','roster_history','shop_items',
 'shop_purchases','cosmetic_inventory','cosmetic_loadouts','player_draws'] loop
 execute format('alter table kickx_private.%I enable row level security',t);
 execute format('revoke all on kickx_private.%I from public,anon,authenticated,service_role',t);
 end loop;
end $$;
alter table public.wallet_ledger drop constraint wallet_ledger_kind_check;
alter table public.wallet_ledger add constraint wallet_ledger_kind_check check(
 kind in('initial','buy','sell','grant','mission_reward','shop','draw','draw_duplicate')
 and (kind<>'grant' or (delta>0 and trade_id is null))
 and (kind<>'mission_reward' or (delta>0 and trade_id is null))
 and (kind not in('shop','draw') or (delta<0 and trade_id is null))
 and (kind<>'draw_duplicate' or (delta>=0 and trade_id is null)));
alter table public.trades drop constraint trades_execution_reason_check;
alter table public.trades add constraint trades_execution_reason_check check(execution_reason in('bench_manual','bench_expired','draw'));
alter table public.holdings drop constraint holdings_bench_valid;
alter table public.holdings add constraint holdings_bench_valid check(
 (bench_price is null and bench_started_at is null and bench_reason is null) or
 (bench_price is not null and bench_price>0 and bench_started_at is not null and bench_reason is not null and bench_reason in('transfer','position','transfer_position','formation','draw')));

create function kickx_private.mission_today() returns date language sql stable set search_path='' as $$
 select (now() at time zone 'Asia/Seoul')::date $$;
create function kickx_private.mission_week(d date) returns date language sql immutable set search_path='' as $$
 select d-((extract(isodow from d)::integer+5)%7) $$;
create function kickx_private.international_week(w date) returns boolean language sql stable security definer set search_path='' as $$
 select not exists(select 1 from public.fixtures f where f.league_id in('bsd-1','bsd-3','bsd-4','bsd-5','bsd-6')
 and f.starts_at>=((w+3)::timestamp at time zone 'Asia/Seoul') and f.starts_at<((w+7)::timestamp at time zone 'Asia/Seoul')
 and f.status not in('CANC','PST')) $$;
create function kickx_private.ensure_mission_day(u uuid,d date) returns void language plpgsql security definer set search_path='' as $$begin
 insert into kickx_private.mission_days(user_id,day,choices)
 select u,d,array(select k from unnest(array['ai_report','player_post','club_post','fixtures','watch']) k
 order by md5(u::text||d::text||k) limit 2) on conflict do nothing;
 if found then
  -- Once per member/day: bound activity storage while retaining financial ledgers.
  delete from kickx_private.mission_events where user_id=u and day<d-35;
  delete from kickx_private.mission_days where user_id=u and day<d-90;
  delete from kickx_private.attendance where user_id=u and day<d-90;
  delete from kickx_private.roster_history old where old.user_id=u and old.recorded_at<((d-35)::timestamp at time zone 'Asia/Seoul')
  and exists(select 1 from kickx_private.roster_history newer where newer.user_id=u and newer.player_id=old.player_id
  and (newer.recorded_at,newer.id)>(old.recorded_at,old.id) and newer.recorded_at<((d-35)::timestamp at time zone 'Asia/Seoul'));
 end if;
end $$;
create function kickx_private.update_daily_clear(u uuid,d date) returns void language sql security definer set search_path='' as $$
 update kickx_private.mission_days m set cleared_at=coalesce(cleared_at,clock_timestamp()) where user_id=u and day=d
 and exists(select 1 from kickx_private.attendance a where a.user_id=u and a.day=d and not a.recovered)
 and not exists(select 1 from unnest(m.choices) k where not exists(
 select 1 from kickx_private.mission_events e where e.user_id=u and e.day=d and e.kind=k)) $$;
create function kickx_private.mission_event(u uuid,k text,t text) returns void
language plpgsql security definer set search_path='' as $$declare d date:=kickx_private.mission_today();begin
 perform kickx_private.ensure_mission_day(u,d);
 insert into kickx_private.mission_events(user_id,day,kind,target) values(u,d,k,t) on conflict do nothing;
 perform kickx_private.update_daily_clear(u,d);
end $$;
create function kickx_private.track_mission_write() returns trigger language plpgsql security definer set search_path='' as $$begin
 if tg_table_name='community_posts' then
  if new.status='published' then perform kickx_private.mission_event(new.author_id,case new.scope when 'player' then 'player_post' else 'club_post' end,new.id::text);end if;
 elsif tg_table_name='community_comments' then
  if new.status='published' then perform kickx_private.mission_event(new.author_id,'comment',new.id::text);end if;
 elsif tg_table_name='watchlists' then perform kickx_private.mission_event(new.user_id,'watch',new.player_id);
 elsif tg_table_name='trades' then
  if new.side='sell' and new.execution_reason is distinct from 'bench_expired' then perform kickx_private.mission_event(new.user_id,'sell',new.id::text);end if;
 end if;return new;
end $$;
create trigger mission_post after insert on public.community_posts for each row execute function kickx_private.track_mission_write();
create trigger mission_comment after insert on public.community_comments for each row execute function kickx_private.track_mission_write();
create trigger mission_watch after insert on public.watchlists for each row execute function kickx_private.track_mission_write();
create trigger mission_sell after insert on public.trades for each row execute function kickx_private.track_mission_write();
create function kickx_private.track_mission_roster() returns trigger language plpgsql security definer set search_path='' as $$begin
 if tg_op='DELETE' then
  insert into kickx_private.roster_history(user_id,player_id,owned,starter) values(old.user_id,old.player_id,false,false);return old;
 end if;
 if tg_op='INSERT' or (new.bench_started_at is null) is distinct from (old.bench_started_at is null) then
  insert into kickx_private.roster_history(user_id,player_id,owned,starter) values(new.user_id,new.player_id,true,new.bench_started_at is null);
 end if;return new;
end $$;
create trigger mission_roster after insert or update of bench_started_at or delete on public.holdings
 for each row execute function kickx_private.track_mission_roster();
create function kickx_private.weekly_progress(u uuid,w date) returns jsonb
language plpgsql stable security definer set search_path='' as $$declare appearances integer;high integer;events jsonb;international boolean:=kickx_private.international_week(w);begin
 select count(distinct r.player_id) filter(where h.starter),count(distinct r.player_id) filter(where r.score>=10)
 into appearances,high from public.performance_results r join public.fixtures f on f.id=r.fixture_id
 join public.player_match_records m on m.player_id=r.player_id and m.fixture_id=r.fixture_id and m.minutes>0
 cross join lateral(select owned,starter from kickx_private.roster_history h where h.user_id=u and h.player_id=r.player_id
 and h.recorded_at<=f.starts_at order by recorded_at desc,id desc limit 1) h
 where h.owned and r.status in('ready','provisional') and f.status in('FT','AET','PEN','AWD','WO')
 and f.league_id in('bsd-1','bsd-3','bsd-4','bsd-5','bsd-6')
 and f.starts_at>=(w::timestamp at time zone 'Asia/Seoul') and f.starts_at<((w+7)::timestamp at time zone 'Asia/Seoul');
 select coalesce(jsonb_object_agg(kind,n),'{}') into events from(select kind,count(*) n from kickx_private.mission_events
 where user_id=u and day>=w and day<w+7 group by kind)e;
 return jsonb_build_object('international',international,'week',w,'endsAt',((w+7)::timestamp at time zone 'Asia/Seoul'),
 'items',jsonb_build_array(
 jsonb_build_object('id',case when international then 'ai_report' else 'appearances' end,'target',case when international then 10 else 7 end,'current',case when international then coalesce((events->>'ai_report')::int,0) else appearances end),
 jsonb_build_object('id',case when international then 'price' else 'high_score' end,'target',case when international then 10 else 1 end,'current',case when international then coalesce((events->>'price')::int,0) else high end),
 jsonb_build_object('id','sell','target',1,'current',coalesce((events->>'sell')::int,0)),
 jsonb_build_object('id','daily_clear','target',5,'current',(select count(*) from kickx_private.mission_days where user_id=u and day>=w and day<w+7 and cleared_at is not null)),
 jsonb_build_object('id','community','target',10,'current',coalesce((events->>'player_post')::int,0)+coalesce((events->>'club_post')::int,0)+coalesce((events->>'comment')::int,0)),
 jsonb_build_object('id','attendance','target',7,'current',(select count(*) from kickx_private.attendance where user_id=u and day>=w and day<w+7))),
 'claimed',(select exists(select 1 from kickx_private.weekly_claims where user_id=u and week=w)));
end $$;
create function kickx_private.external_delta(u uuid,s timestamptz default null,e timestamptz default null)
returns bigint language sql stable security definer set search_path='' as $$
 select coalesce(sum(delta),0)::bigint from public.wallet_ledger where user_id=u and kind in('mission_reward','shop')
 and (s is null or created_at>=s) and (e is null or created_at<e) $$;
create function kickx_private.pending_draw_value(u uuid,t timestamptz default null) returns bigint
language sql stable security definer set search_path='' as $$
 select count(*)*100000 from kickx_private.player_draws where user_id=u and created_at<=coalesce(t,clock_timestamp())
 and (settled_at is null or settled_at>coalesce(t,clock_timestamp())) $$;
create function kickx_private.draw_pool() returns table(id text,name text,price bigint)
language sql stable security definer set search_path='' as $$
 select p.id,coalesce(p.name_ko,n.display_name,p.name),s.price::bigint
 from public.players p join public.teams t on t.id=p.team_id join public.player_market_snapshots s on s.id=p.id
 left join public.player_names n on n.player_id=p.id where t.league_id in('bsd-1','bsd-3','bsd-4','bsd-5','bsd-6')
 and p.position in('GK','DF','MF','FW') and p.trade_status is null and s.price>0 and s.pricing_status='ready' $$;

create function public.kickx_engagement() returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=public.kickx_require_member();d date:=kickx_private.mission_today();w date:=kickx_private.mission_week(d);day_row kickx_private.mission_days%rowtype;begin
 perform kickx_private.ensure_mission_day(u,d);
 select * into strict day_row from kickx_private.mission_days where user_id=u and day=d;
 return jsonb_build_object('day',d,'resetsAt',((d+1)::timestamp at time zone 'Asia/Seoul'),
 'daily',jsonb_build_object('items',(
 select jsonb_agg(jsonb_build_object('id',k,'target',1,'current',case when k='attendance' then
 (select count(*) from kickx_private.attendance a where a.user_id=u and a.day=d and not a.recovered)
 else (select least(1,count(*)) from kickx_private.mission_events e where e.user_id=u and e.day=d and e.kind=k) end) order by ord)
 from unnest(array['attendance']||day_row.choices) with ordinality x(k,ord)),
 'cleared',day_row.cleared_at is not null,'claimed',day_row.claimed_at is not null,'reward',1000),
 'weekly',kickx_private.weekly_progress(u,w)||jsonb_build_object('reward',10000),
 'attendance',coalesce((select jsonb_agg(jsonb_build_object('day',day,'recovered',recovered) order by day)
 from kickx_private.attendance where user_id=u and day>=w and day<w+7),'[]'),
 'catalog',(select jsonb_agg(to_jsonb(i) order by sort_order) from kickx_private.shop_items i),
 'inventory',coalesce((select jsonb_object_agg(item_id,quantity) from kickx_private.cosmetic_inventory where user_id=u),'{}'),
 'loadout',coalesce((select to_jsonb(l)-'user_id' from kickx_private.cosmetic_loadouts l where user_id=u),'{"faces":false}'::jsonb),
 'unclaimedDaily',coalesce((select jsonb_agg(day order by day) from kickx_private.mission_days where user_id=u and day<d and day>=d-7 and cleared_at is not null and claimed_at is null),'[]'),
 'draw',jsonb_build_object('price',100000,'poolSize',(select count(*) from kickx_private.draw_pool()),'remaining',case when exists(select 1 from kickx_private.player_draws where user_id=u and day=d) then 0 else 1 end,
 'pending',coalesce((select jsonb_agg(to_jsonb(p)-'user_id'-'request_id' order by created_at) from kickx_private.player_draws p where user_id=u and status='pending'),'[]'),
 'history',coalesce((select jsonb_agg(to_jsonb(p)-'user_id'-'request_id' order by created_at desc) from(select * from kickx_private.player_draws where user_id=u order by created_at desc limit 20)p),'[]')));
end $$;

-- View receipts are validated against existing server data; never accept a client counter.
create function public.kickx_mission_view(p_kind text,p_target text) returns void
language plpgsql security definer set search_path='' as $$declare u uuid:=public.kickx_require_active_member();a text[];begin
 if p_kind='fixtures' then
  if p_target<>'schedule' then raise exception 'INVALID_INPUT';end if;
 elsif p_kind='price' then
  if not exists(select 1 from public.players p join public.teams t on t.id=p.team_id join public.player_market_snapshots s on s.id=p.id
  where p.id=p_target and s.price>0 and t.league_id in('bsd-1','bsd-3','bsd-4','bsd-5','bsd-6')) then raise exception 'INVALID_TARGET';end if;
 elsif p_kind='ai_report' then
  a:=string_to_array(p_target,':');
  if cardinality(a)<>2 or not exists(select 1 from public.player_analyses r where r.id=a[1] and r.fixture_id=a[2]
  and r.status='ready' and r.prompt_version='match-report-points-v5') then raise exception 'REPORT_NOT_READY';end if;
 else raise exception 'INVALID_ACTION';end if;
 perform kickx_private.mission_event(u,p_kind,p_target);
end $$;

create function public.kickx_engagement_action(p_action text,p_input jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare u uuid:=public.kickx_require_active_member();d date:=kickx_private.mission_today();w date:=kickx_private.mission_week(d);
 bal bigint;amount bigint;claim_day date;progress jsonb;i kickx_private.shop_items%rowtype;purchase kickx_private.shop_purchases%rowtype;
 req uuid;selected_category text;item text;recovery date;begin
 perform public.kickx_economy_lock();perform public.kickx_open_wallet();
 perform kickx_private.ensure_mission_day(u,d);
 if p_action='attendance' then
  insert into kickx_private.attendance(user_id,day) values(u,d) on conflict do nothing;
  perform kickx_private.update_daily_clear(u,d);
 elsif p_action='claim_daily' then
  claim_day:=coalesce((p_input->>'day')::date,d);
  if claim_day<d-7 or claim_day>d then raise exception 'INVALID_INPUT';end if;
  update kickx_private.mission_days set claimed_at=clock_timestamp() where user_id=u and day=claim_day and cleared_at is not null and claimed_at is null;
  if found then amount:=1000;elsif not exists(select 1 from kickx_private.mission_days where user_id=u and day=claim_day and claimed_at is not null) then raise exception 'MISSIONS_INCOMPLETE';end if;
 elsif p_action='claim_weekly' then
  progress:=kickx_private.weekly_progress(u,w);
  if exists(select 1 from jsonb_array_elements(progress->'items') x where (x->>'current')::int<(x->>'target')::int) then raise exception 'MISSIONS_INCOMPLETE';end if;
  insert into kickx_private.weekly_claims(user_id,week,international) values(u,w,(progress->>'international')::boolean) on conflict do nothing;
  if found then amount:=10000;end if;
 elsif p_action='purchase' then
  req:=(p_input->>'requestId')::uuid;
  if req is null then raise exception 'INVALID_INPUT';end if;
  select * into purchase from kickx_private.shop_purchases where user_id=u and request_id=req;
  if found then
   if purchase.item_id is distinct from p_input->>'itemId' then raise exception 'REQUEST_REUSED';end if;
   return public.kickx_engagement();
  end if;
  select * into i from kickx_private.shop_items where id=p_input->>'itemId';
  if not found then raise exception 'INVALID_TARGET';end if;
  if i.category<>'ticket' and exists(select 1 from kickx_private.cosmetic_inventory where user_id=u and item_id=i.id) then raise exception 'ITEM_OWNED';end if;
  select balance into strict bal from public.wallets where user_id=u for update;
  if bal<i.price then raise exception 'INSUFFICIENT_POINTS';end if;
  insert into kickx_private.shop_purchases(user_id,item_id,price,request_id) values(u,i.id,i.price,req);
  insert into kickx_private.cosmetic_inventory(user_id,item_id,quantity) values(u,i.id,1)
   on conflict(user_id,item_id) do update set quantity=kickx_private.cosmetic_inventory.quantity+1;
  bal:=bal-i.price;update public.wallets set balance=bal where user_id=u;
  insert into public.wallet_ledger(user_id,kind,delta,balance_after) values(u,'shop',-i.price,bal);
 elsif p_action='equip' then
  selected_category:=p_input->>'category';item:=nullif(p_input->>'itemId','');
  if selected_category is null or selected_category not in('nameplate','frame','pitch','faces') then raise exception 'INVALID_INPUT';end if;
  if selected_category<>'faces' and item is not null and not exists(select 1 from kickx_private.cosmetic_inventory inv
  join kickx_private.shop_items s on s.id=inv.item_id where inv.user_id=u and inv.item_id=item and inv.quantity>0 and s.category=selected_category) then raise exception 'ITEM_NOT_OWNED';end if;
  insert into kickx_private.cosmetic_loadouts(user_id) values(u) on conflict do nothing;
  if selected_category='faces' then
   if jsonb_typeof(p_input->'enabled') is distinct from 'boolean' then raise exception 'INVALID_INPUT';end if;
   update kickx_private.cosmetic_loadouts set faces=(p_input->>'enabled')::boolean where user_id=u;
  else execute format('update kickx_private.cosmetic_loadouts set %I=$1 where user_id=$2',selected_category) using item,u;end if;
 elsif p_action='recover' then
  recovery:=(p_input->>'day')::date;
  if recovery is null or recovery<w or recovery>=d or recovery<(select (created_at at time zone 'Asia/Seoul')::date from public.profiles where id=u) then raise exception 'INVALID_RECOVERY_DAY';end if;
  if exists(select 1 from kickx_private.attendance where user_id=u and day=recovery) then return public.kickx_engagement();end if;
  update kickx_private.cosmetic_inventory set quantity=quantity-1 where user_id=u and item_id='attendance-ticket' and quantity>0;
  if not found then raise exception 'NO_RECOVERY_TICKET';end if;
  insert into kickx_private.attendance(user_id,day,recovered) values(u,recovery,true);
 else raise exception 'INVALID_ACTION';end if;
 if amount is not null then
  update public.wallets set balance=balance+amount where user_id=u returning balance into bal;
  insert into public.wallet_ledger(user_id,kind,delta,balance_after) values(u,'mission_reward',amount,bal);
 end if;
 if amount is not null or p_action='purchase' then insert into public.asset_snapshots(user_id,value) values(u,public.kickx_assets(u));end if;
 return public.kickx_engagement();
end $$;

create function public.kickx_nameplates(p_users uuid[]) returns jsonb
language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_object_agg(l.user_id,l.nameplate),'{}') from kickx_private.cosmetic_loadouts l
 where l.user_id=any(p_users[1:100]) and l.nameplate is not null $$;

create function public.kickx_draw(p_request uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare u uuid:=public.kickx_require_active_member();d date:=kickx_private.mission_today();r kickx_private.player_draws%rowtype;
 chosen record;pool integer;bal bigint;comp bigint;begin
 perform public.kickx_economy_lock();
 if p_request is null then raise exception 'INVALID_INPUT';end if;
 select * into r from kickx_private.player_draws where user_id=u and request_id=p_request;
 if found then return to_jsonb(r)-'user_id'-'request_id';end if;
 if exists(select 1 from kickx_private.player_draws where user_id=u and day=d) then raise exception 'DRAW_DAILY_LIMIT';end if;
 if exists(select 1 from kickx_private.player_draws where user_id=u and status='pending') then raise exception 'DRAW_PENDING';end if;
 perform public.kickx_open_wallet();
 select balance into strict bal from public.wallets where user_id=u for update;
 if bal<100000 then raise exception 'INSUFFICIENT_POINTS';end if;
 -- Exactly the same eligible set for count and selection; owned/locked players remain in the pool.
 with eligible as materialized(select * from kickx_private.draw_pool())
 select *,count(*) over()::int as pool from eligible order by random() limit 1 into chosen;
 if not found then raise exception 'DRAW_POOL_EMPTY';end if;
 bal:=bal-100000;
 insert into kickx_private.player_draws(user_id,day,player_id,player_name,price_at_draw,pool_size,request_id)
 values(u,d,chosen.id,chosen.name,chosen.price,chosen.pool,p_request) returning * into r;
 update public.wallets set balance=bal where user_id=u;
 insert into public.wallet_ledger(user_id,kind,delta,balance_after) values(u,'draw',-100000,bal);
 if exists(select 1 from public.holdings where user_id=u and player_id=chosen.id) then
  comp:=chosen.price-round(chosen.price*(select sell_fee_bps from public.kickx_policy)/10000.0)::bigint;
  bal:=bal+comp;update public.wallets set balance=bal where user_id=u;
  insert into public.wallet_ledger(user_id,kind,delta,balance_after) values(u,'draw_duplicate',comp,bal);
  update kickx_private.player_draws set status='duplicate',compensation=comp,settled_at=clock_timestamp() where id=r.id returning * into r;
 end if;
 insert into public.asset_snapshots(user_id,value) values(u,public.kickx_assets(u));
 return to_jsonb(r)-'user_id'-'request_id';
end $$;

create function public.kickx_place_draw(p_draw uuid,p_bench text default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare u uuid:=public.kickx_require_active_member();r kickx_private.player_draws%rowtype;s public.squads%rowtype;
 q uuid;t uuid;bal bigint;n text;pos text;cap integer;used integer;incoming_bench boolean;begin
 perform public.kickx_economy_lock();
 select * into r from kickx_private.player_draws where id=p_draw and user_id=u for update;
 if not found then raise exception 'DRAW_NOT_FOUND';end if;
 if r.status<>'pending' then return to_jsonb(r)-'user_id'-'request_id';end if;
 if exists(select 1 from public.holdings where user_id=u and player_id=r.player_id) then
  select balance into strict bal from public.wallets where user_id=u for update;
  bal:=bal+r.price_at_draw-round(r.price_at_draw*(select sell_fee_bps from public.kickx_policy)/10000.0)::bigint;
  update public.wallets set balance=bal where user_id=u;
  insert into public.wallet_ledger(user_id,kind,delta,balance_after) values(u,'draw_duplicate',r.price_at_draw-round(r.price_at_draw*(select sell_fee_bps from public.kickx_policy)/10000.0)::bigint,bal);
  update kickx_private.player_draws set status='duplicate',compensation=r.price_at_draw-round(r.price_at_draw*(select sell_fee_bps from public.kickx_policy)/10000.0)::bigint,settled_at=clock_timestamp() where id=r.id returning * into r;
  insert into public.asset_snapshots(user_id,value) values(u,public.kickx_assets(u));
  return to_jsonb(r)-'user_id'-'request_id';
 end if;
 select * into s from public.squads where user_id=u for update;
 select position into pos from public.players where id=r.player_id;
 select count(*) into cap from unnest(kickx_private.formation_positions(coalesce(s.formation_id,'4-3-3'))) x where x=pos;
 select count(*) into used from public.holdings h join public.players p on p.id=h.player_id where h.user_id=u and h.bench_started_at is null and p.position=pos;
 incoming_bench:=p_bench=r.player_id;
 if p_bench is not null and not incoming_bench then
  if not exists(select 1 from public.holdings h join public.players p on p.id=h.player_id where h.user_id=u and h.player_id=p_bench
  and h.bench_started_at is null and (used<cap or p.position=pos)) then raise exception 'INVALID_BENCH_SELECTION';end if;
  if (public.kickx_trade_window(p_bench,clock_timestamp())->>'locked')::boolean then raise exception 'MATCH_TRADING_LOCKED';end if;
  update public.holdings h set bench_price=coalesce((select price from public.player_market_snapshots where id=h.player_id),h.cost),bench_started_at=clock_timestamp(),bench_reason='draw' where user_id=u and player_id=p_bench;
 elsif not coalesce(incoming_bench,false) and (used>=cap or (select count(*) from public.holdings where user_id=u and bench_started_at is null)>=11) then raise exception 'DRAW_BENCH_REQUIRED';end if;
 if not coalesce(incoming_bench,false) and (public.kickx_trade_window(r.player_id,clock_timestamp())->>'locked')::boolean then raise exception 'DRAW_LOCKED_USE_BENCH';end if;
 if not coalesce(incoming_bench,false) then perform public.kickx_require_position_capacity(u,r.player_id);end if;
 -- A draw is already paid. The trade records ownership history with a zero-delta ledger entry.
 insert into public.trade_quotes(user_id,player_id,side,price,fee,net,market_at,policy_version,expires_at)
 values(u,r.player_id,'buy',100000,0,100000,r.created_at,(select version from public.kickx_policy),clock_timestamp()+interval '1 minute') returning id into q;
 insert into public.trades(user_id,player_id,player_name,side,price,fee,net,quote_id,request_id,policy_version,execution_reason)
 values(u,r.player_id,r.player_name,'buy',100000,0,100000,q,r.id,(select version from public.kickx_policy),'draw') returning id into t;
 insert into public.holdings(user_id,player_id,cost,trade_id,bench_price,bench_started_at,bench_reason)
 values(u,r.player_id,100000,t,case when incoming_bench then r.price_at_draw end,case when incoming_bench then clock_timestamp() end,case when incoming_bench then 'draw' end);
 select balance into strict bal from public.wallets where user_id=u;
 insert into public.wallet_ledger(user_id,kind,delta,balance_after,trade_id) values(u,'buy',0,bal,t);
 update kickx_private.player_draws set status='placed',bench_player=p_bench,settled_at=clock_timestamp() where id=r.id returning * into r;
 perform kickx_private.kickx_sync_owned_squad(u);
 update public.player_market_snapshots set volume=coalesce(volume,0)+1 where id=r.player_id;
 insert into public.asset_snapshots(user_id,value) values(u,public.kickx_assets(u));
 return to_jsonb(r)-'user_id'-'request_id';
end $$;

-- Preserve the existing API contract while separating mission income/shop spending from trading ROI.
do $$declare src text;changed text;fn text;begin
 src:=pg_get_functiondef('public.kickx_assets(uuid)'::regprocedure);
 changed:=replace(src,'select w.balance+','select w.balance+kickx_private.pending_draw_value(u)+');
 if changed=src then raise exception 'ENGAGEMENT_ASSETS_PATCH_MISMATCH';end if;execute changed;
 src:=pg_get_functiondef('public.kickx_assets_at(uuid,timestamptz)'::regprocedure);
 changed:=replace(src,'select coalesce((select sum(delta)','select kickx_private.pending_draw_value(u,at_time)+coalesce((select sum(delta)');
 if changed=src then raise exception 'ENGAGEMENT_HISTORY_PATCH_MISMATCH';end if;execute changed;
 src:=pg_get_functiondef('public.kickx_member_data()'::regprocedure);
 changed:=replace(src,'total:=w.balance+assets;','total:=w.balance+assets+kickx_private.pending_draw_value(u);');
 changed:=replace(changed,'total-w.initial_points','total-w.initial_points-kickx_private.external_delta(u)');
 changed:=replace(changed,'''points'',w.balance,','''points'',w.balance,''pendingDrawAssets'',kickx_private.pending_draw_value(u),');
 changed:=replace(changed,'case t.execution_reason when','case t.execution_reason when ''draw'' then ''선수 뽑기'' when');
 if changed=src then raise exception 'ENGAGEMENT_MEMBER_PATCH_MISMATCH';end if;execute changed;
 foreach fn in array array['public.kickx_refresh_rankings()','public.kickx_auto_refresh_rankings()'] loop
  src:=pg_get_functiondef(fn::regprocedure);
  changed:=replace(src,'(assets-baseline)*100.0/baseline','(assets-baseline-kickx_private.external_delta(user_id,start_time,end_time))*100.0/baseline');
  if changed=src then raise exception 'ENGAGEMENT_RANKING_PATCH_MISMATCH';end if;execute changed;
 end loop;
end $$;
-- No internal helper can be called through PostgREST or a member database role.
do $$declare p record;begin
 for p in select oid::regprocedure fn from pg_proc where pronamespace='kickx_private'::regnamespace
 and proname in('mission_today','mission_week','international_week','ensure_mission_day','update_daily_clear','mission_event',
 'track_mission_write','track_mission_roster','weekly_progress','external_delta','pending_draw_value','draw_pool') loop
 execute format('revoke all on function %s from public,anon,authenticated,service_role',p.fn);end loop;
end $$;
revoke all on function public.kickx_engagement(),public.kickx_engagement_action(text,jsonb),public.kickx_mission_view(text,text),public.kickx_draw(uuid),public.kickx_place_draw(uuid,text) from public,anon,authenticated,service_role;
grant execute on function public.kickx_engagement(),public.kickx_engagement_action(text,jsonb),public.kickx_mission_view(text,text),public.kickx_draw(uuid),public.kickx_place_draw(uuid,text) to authenticated;
revoke all on function public.kickx_nameplates(uuid[]) from public,anon,authenticated,service_role;
grant execute on function public.kickx_nameplates(uuid[]) to anon,authenticated;
notify pgrst,'reload schema';
commit;
