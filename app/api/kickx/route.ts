import { connection } from "next/server";
import { getKickxRepository } from "@/server/kickx/repository";
import { readPlatform } from "@/server/kickx/service";
import { timedRead } from "@/server/kickx/read-timing";
import { failure } from "@/server/kickx/http";
import { SCORING_REVISION } from '@/server/kickx/engine/report-policy';
export async function GET() {
  await connection();
  return timedRead(async()=>{
  try {
    return Response.json(await readPlatform(getKickxRepository()), {
      headers: { "Cache-Control": "private, no-store", "X-Kickx-Policy-Support": "report-v3", "X-Kickx-Pricing-Revision": "launch-dnp-regular-20261030", "X-Kickx-Scoring-Revision":SCORING_REVISION },
    });
  } catch (error) { return failure(error); }
  });
}
