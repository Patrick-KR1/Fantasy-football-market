-- Record administrator-authorized point grants without rewriting initial funds
-- or misclassifying a grant as a player sale. Existing RLS/privileges stay intact.
begin;
alter table public.wallet_ledger drop constraint wallet_ledger_kind_check;
alter table public.wallet_ledger add constraint wallet_ledger_kind_check
 check(kind in('initial','buy','sell','grant')and(kind<>'grant'or(delta>0 and trade_id is null)));
commit;
