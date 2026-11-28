-- Preserve an empty result array for players with a frozen price but no matches.
begin;
do $patch$declare original text;changed text;begin
 original:=pg_get_functiondef('kickx_private.apply_balanced_assessments(jsonb,text)'::regprocedure);
 changed:=replace(original,'results=(select jsonb_agg','results=coalesce((select jsonb_agg');
 if changed=original then raise exception 'BALANCED_EMPTY_RESULTS_PATCH_REQUIRED';end if;
 original:=changed;
 changed:=replace(original,$from$where r.player_id=p.player_id and r.rule_version='report-v3')
 from pg_temp.balanced_plans$from$,$to$where r.player_id=p.player_id and r.rule_version='report-v3'),'[]'::jsonb)
 from pg_temp.balanced_plans$to$);
 if changed=original then raise exception 'BALANCED_EMPTY_RESULTS_PATCH_REQUIRED';end if;
 execute changed;
end $patch$;
revoke all on function kickx_private.apply_balanced_assessments(jsonb,text)from public,anon,authenticated,service_role;
commit;
