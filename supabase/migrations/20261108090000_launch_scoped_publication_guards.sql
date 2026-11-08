-- Historical scoring errors remain visible, but cannot withhold a price that
-- only uses completed post-launch games. Keep all other publication checks.
begin;
do $patch$
declare original text; amended text; before_guard text; latest_guard text;
begin
 original:=pg_get_functiondef('public.kickx_publish_calculation(uuid,text,text,jsonb,jsonb)'::regprocedure);
 before_guard:=$from$and public.kickx_regular_fixture(z.id) is true)) and old.status$from$;
 latest_guard:=$from$and f.season>(p.report_reference->>'season')::integer and f.status='FT' and x->>'status'='blocked') else$from$;
 if position(before_guard in original)=0 or position(latest_guard in original)=0 then
  raise exception 'PUBLICATION_SCOPE_GUARDS_CHANGED';
 end if;
 -- The old-score protection still applies to every price-affecting match.
 -- A frozen reference/initial price does not depend on mutable pre-launch scores.
 amended:=replace(original,before_guard,$to$and public.kickx_regular_fixture(z.id) is true
  and coalesce(extract(epoch from public.kickx_fixture_valuation_at(z.id))*1000>=coalesce((p.report_parameters->>'valuationStartMs')::numeric,0),true))) and old.status$to$);
 -- Match the exact end-time predicate used by kickx_report_plan, including a
 -- game that starts before launch but finishes at/after it. Unknown time blocks.
 amended:=replace(amended,latest_guard,$to$and f.season>(p.report_reference->>'season')::integer and f.status='FT' and x->>'status'='blocked'
  and coalesce(extract(epoch from public.kickx_fixture_valuation_at(f.id))*1000>=coalesce((p.report_parameters->>'valuationStartMs')::numeric,0),true)) else$to$);
 execute amended;
end $patch$;
notify pgrst,'reload schema';
commit;
