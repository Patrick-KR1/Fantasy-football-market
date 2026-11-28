-- Whole-table fingerprints use sequential reads; separate RPC calls keep each
-- backup check below the API statement timeout without relaxing that timeout.
begin;
alter function public.kickx_balanced_replay_state()set enable_indexscan=off;
alter function public.kickx_balanced_replay_state()set enable_bitmapscan=off;
create function public.kickx_balanced_replay_state(p_part text)returns jsonb language plpgsql stable
set search_path=''set jit=off set timezone='UTC' set enable_indexscan=off set enable_bitmapscan=off as $$
declare value jsonb;begin
 case p_part
 when 'financial'then value:=public.kickx_valuation_integrity();
 when 'policy'then select to_jsonb(md5(jsonb_build_array(version,report_parameters,report_reference->>'hash')::text))into value from public.kickx_policy;
 when 'sources'then select to_jsonb(md5(string_agg(player_id||'|'||fixture_id||'|'||updated_at::text,','order by player_id,fixture_id)))into value from public.football_match_stats;
 when 'fixtures'then select to_jsonb(md5(string_agg(id||'|'||updated_at::text,','order by id)))into value from public.fixtures;
 when 'eventSources'then select to_jsonb(md5(string_agg(fixture_id||'|'||updated_at::text,','order by fixture_id)))into value from public.football_event_sources;
 when 'scores'then select to_jsonb(md5(string_agg(player_id||'|'||fixture_id||'|'||coalesce(input_hash,'')||'|'||calculated_at::text,','order by player_id,fixture_id)))into value from public.performance_results;
 when 'revisions'then select to_jsonb(md5(string_agg(id::text||'|'||input_hash||'|'||coalesce(archive_path,'')||'|'||coalesce(archived_at::text,''),','order by id)))into value from public.calculation_revisions;
 when 'initial'then select to_jsonb(md5(string_agg(player_id||'|'||detail::text,','order by player_id)))into value from public.player_initial_values;
 else raise exception 'BALANCED_INVALID_STATE_PART';end case;
 return jsonb_build_object(p_part,value);
end $$;
revoke all on function public.kickx_balanced_replay_state(text)from public,anon,authenticated;
grant execute on function public.kickx_balanced_replay_state(text)to service_role;
notify pgrst,'reload schema';
commit;
