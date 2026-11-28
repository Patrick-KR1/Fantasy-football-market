export type PredictionChoice = 'win' | 'draw' | 'loss';
export const predictionLabels: Record<PredictionChoice, string> = { win: '승', draw: '무', loss: '패' };
export type PredictionMatch = {
 id: string; homeId: string; awayId: string; homeName: string; awayName: string;
 startsAt: string; status: string; homeScore: number | null; awayScore: number | null;
 penaltiesHome: number | null; penaltiesAway: number | null; leagueName: string | null;
 canPredict: boolean; choice: PredictionChoice | null; actual: PredictionChoice | null;
 reward: number | null; settledAt: string | null;
};
export type Predictions = { teamId: string | null; teamName: string | null; serverTime: string | null; past: PredictionMatch[]; upcoming: PredictionMatch[] };
export const emptyPredictions = (): Predictions => ({ teamId: null, teamName: null, serverTime: null, past: [], upcoming: [] });
