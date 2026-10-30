-- JSON expansion estimates trigger expensive JIT compilation on the production
-- audit (13.3 seconds vs 3.1 seconds without JIT), exceeding the API's 8s limit.
-- Limit this setting to the two internal bulk JSON scans; public requests and
-- the database-wide timeout/permissions remain unchanged.
alter function public.kickx_valuation_data_audit() set jit=off;
alter function public.kickx_seed_non_participation() set jit=off;
