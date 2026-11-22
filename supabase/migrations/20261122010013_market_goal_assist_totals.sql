-- Market counters show confirmed totals from imported matches. One unknown
-- match must not hide goals/assists already recorded in other matches.
-- SUM keeps an entirely unknown metric NULL and preserves a verified zero.
-- Patch both the importer and the scheduled rebuild, keeping their existing
-- season/competition/appearance filters, privileges and valuation rules.
do $migration$
declare
  routine text;
  metric text;
  definition text;
  revised text;
begin
  foreach routine in array array[
    'public.apply_bsd_batch(jsonb)',
    'public.kickx_report_refresh_summaries()'
  ] loop
    definition := pg_get_functiondef(routine::regprocedure);
    foreach metric in array array['goals', 'assists'] loop
      revised := regexp_replace(
        definition,
        format($pattern$case\s+when\s+count\(ms\.normalized#>>'\{values,%1$s\}'\)\s*=\s*count\(\*\)\s*then\s+sum\(\(ms\.normalized#>>'\{values,%1$s\}'\)::integer\)\s*end$pattern$, metric),
        format('sum((ms.normalized#>>''{values,%s}'')::integer)', metric),
        'g'
      );
      if revised = definition then
        raise exception 'Expected % aggregate not found in %', metric, routine;
      end if;
      definition := revised;
    end loop;
    execute definition;
  end loop;
end
$migration$;

-- Repair the display summaries already stored in the deployed database.
select public.kickx_report_refresh_summaries();
