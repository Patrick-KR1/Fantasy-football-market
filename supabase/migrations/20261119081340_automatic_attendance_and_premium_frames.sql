begin;
set local lock_timeout='10s';
select public.kickx_economy_lock();

update kickx_private.shop_items set price=5000 where id='attendance-ticket';
update kickx_private.shop_items set sort_order=sort_order+4 where category='pitch';
update kickx_private.shop_items set sort_order=17 where id='attendance-ticket';
insert into kickx_private.shop_items(id,category,name,description,price,theme,sort_order) values
 ('frame-seraph','frame','세라프 윙','황금 날개와 왕관, 빛나는 보석이 감싸는 천상의 테두리',30000,'seraph',8),
 ('frame-dragon','frame','드래곤 플레어','용의 날개와 뿔, 타오르는 불꽃의 붉은 테두리',35000,'dragon',9),
 ('frame-astral','frame','아스트랄 오빗','회전하는 이중 궤도와 별빛이 흐르는 성운 테두리',40000,'astral',10),
 ('frame-tempest','frame','템페스트 크라운','빛나는 번개와 금속 왕관의 청록 테두리',35000,'tempest',11);
alter table kickx_private.cosmetic_loadouts alter column faces set default true;
update kickx_private.cosmetic_loadouts set faces=true where not faces;

create function kickx_private.auto_attendance(u uuid,d date) returns void
language plpgsql security definer set search_path='' as $$begin
 if exists(select 1 from public.member_restrictions where user_id=u and suspended_until>now()) then return;end if;
 insert into kickx_private.attendance(user_id,day) values(u,d) on conflict do nothing;
 if found then perform kickx_private.update_daily_clear(u,d);end if;
end $$;
revoke all on function kickx_private.auto_attendance(uuid,date) from public,anon,authenticated,service_role;
do $$declare src text;changed text;begin
 src:=pg_get_functiondef('public.kickx_engagement()'::regprocedure);
 changed:=replace(src,'perform kickx_private.ensure_mission_day(u,d);',
 'perform kickx_private.ensure_mission_day(u,d); perform kickx_private.auto_attendance(u,d);');
 changed:=replace(changed,'{"faces":false}','{"faces":true}');
 if changed=src or strpos(changed,'auto_attendance(u,d)')=0 then raise exception 'AUTO_ATTENDANCE_PATCH_MISMATCH';end if;
 execute changed;
end $$;
notify pgrst,'reload schema';
commit;
