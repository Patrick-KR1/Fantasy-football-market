import { PGlite } from '@electric-sql/pglite';
import { readFile, readdir } from 'node:fs/promises';
const db=new PGlite();
try {
 await db.exec(await readFile('tests/database-bootstrap.sql','utf8'));
 for(const f of (await readdir('supabase/migrations')).filter(f=>f.endsWith('.sql')).sort()) {await db.exec(await readFile('supabase/migrations/'+f,'utf8'));console.log('migration',f);}
 await db.exec('update public.kickx_policy set club_competitions_enabled=false');
 // New members start with 1,000,000P; the fixtures below were written for the earlier 1,300,000P grant.
 const grant=(await db.query('select initial_points from public.kickx_policy')).rows[0]?.initial_points;
 if(Number(grant)!==1000000) throw Error('Initial grant must be 1,000,000P, got '+grant);
 await db.exec('update public.kickx_policy set initial_points=1300000');
 for(const f of (await readdir('tests')).filter(f=>/^database-(?!bootstrap).*\.sql$/.test(f)).sort()) {await db.exec(await readFile('tests/'+f,'utf8'));console.log('passed',f);}
} catch(error) {console.error(error.message, error.code, error.where ?? "");process.exitCode=1;} finally {await db.close();}
