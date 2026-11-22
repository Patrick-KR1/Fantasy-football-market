-- 30-day trend for list views (home, market list and cards), which do not carry full price history.
-- One value per Korean day (the last of that day), preceded by the last value before the window so a
-- player whose price moved rarely still draws a line. Read-only over the public price_history table.
create function public.kickx_player_trends(p_players text[]) returns jsonb
language sql stable security invoker set search_path='' as $$
 with ids as(select distinct unnest(p_players[1:60]) id),
 daily as(select distinct on(h.player_id,(h.recorded_at at time zone 'Asia/Seoul')::date) h.player_id,h.recorded_at,h.value
  from public.price_history h join ids on ids.id=h.player_id
  where h.recorded_at>=now()-interval '30 days'
  order by h.player_id,(h.recorded_at at time zone 'Asia/Seoul')::date,h.recorded_at desc,h.id desc),
 anchor as(select ids.id player_id,a.recorded_at,a.value from ids cross join lateral(
  select h.recorded_at,h.value from public.price_history h where h.player_id=ids.id and h.recorded_at<now()-interval '30 days'
  order by h.recorded_at desc,h.id desc limit 1) a),
 series as(select player_id,jsonb_agg(jsonb_build_object('at',recorded_at,'value',value) order by recorded_at) points
  from(select * from anchor union all select * from daily) s group by player_id)
 select coalesce(jsonb_object_agg(player_id,points),'{}'::jsonb) from series
$$;
revoke all on function public.kickx_player_trends(text[]) from public;
grant execute on function public.kickx_player_trends(text[]) to anon,authenticated,service_role;
notify pgrst,'reload schema';
