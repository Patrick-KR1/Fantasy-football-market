-- Product artwork and prices are public; inventory, progress and purchases stay private.
begin;
create function public.kickx_shop_catalog() returns jsonb
language sql stable security definer set search_path='' as $$
 select jsonb_build_object('catalog',(select jsonb_agg(to_jsonb(s) order by sort_order) from kickx_private.shop_items s),
 'poolSize',(select count(*) from kickx_private.draw_pool()))
$$;
revoke all on function public.kickx_shop_catalog() from public,anon,authenticated,service_role;
grant execute on function public.kickx_shop_catalog() to anon,authenticated;
comment on function public.kickx_shop_catalog() is 'Public product catalog and aggregate draw pool count only; no member data.';
notify pgrst,'reload schema';
commit;
