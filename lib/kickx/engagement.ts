export type Mission = { id: string; current: number; target: number };
export type ShopCategory = 'nameplate' | 'frame' | 'pitch' | 'ticket';
export type ShopItem = { id: string; category: ShopCategory; name: string; description: string; price: number; theme: string };
export type Loadout = { nameplate?: string | null; frame?: string | null; pitch?: string | null; faces: boolean };
export const emptyShop = (): {catalog:ShopItem[];poolSize:number} => ({catalog:[],poolSize:0});
export type DrawReceipt = { id: string; day: string; player_id: string; player_name: string; price_at_draw: number; pool_size: number; status: 'pending' | 'placed' | 'duplicate'; compensation: number | null; bench_player: string | null; created_at: string };
export type Engagement = {
 day: string; resetsAt: string;
 daily: { items: Mission[]; cleared: boolean; claimed: boolean; reward: number };
 weekly: { week: string; endsAt: string; international: boolean; items: Mission[]; claimed: boolean; reward: number; itemReward?: number; claimedItems?: string[] };
 attendance: { day: string; recovered: boolean }[];
 catalog: ShopItem[]; inventory: Record<string, number>; loadout: Loadout; unclaimedDaily: string[];
 draw: { price: number; poolSize?: number; remaining: number; pending: DrawReceipt[]; history: DrawReceipt[] };
 /** Frame chosen for one player (player id → frame item id); others use loadout.frame. */
 playerFrames?: Record<string, string>;
 /** False while the per-player frame tables are not available on the server. */
 playerFramesReady?: boolean;
};
export const emptyEngagement = (): Engagement => ({ day: '', resetsAt: '', daily: { items: [], cleared: false, claimed: false, reward: 1000 }, weekly: { week: '', endsAt: '', international: false, items: [], claimed: false, reward: 4000, claimedItems: [] }, attendance: [], catalog: [], inventory: {}, loadout: { faces: true }, unclaimedDaily: [], draw: { price: 100000, remaining: 0, pending: [], history: [] } });
export const MISSION_LABELS: Record<string, string> = {
 attendance: '출석 체크', ai_report: '선수 AI 리포트 조회', player_post: '선수 커뮤니티 글 작성', club_post: '구단 커뮤니티 글 작성', fixtures: '경기 일정 확인', watch: '관심 선수 등록',
 appearances: '보유 스쿼드 선수 중 주간 출전 7명', high_score: '보유 선수 Performance 10점 이상 1명', sell: '선수 1명 매각', daily_clear: '일일 미션 5일 모두 클리어', community: '커뮤니티 글·댓글 참여 10회', price: '선수 시세 조회',
};
export const MISSION_LINKS: Record<string, string> = { ai_report: '/market', player_post: '/market', club_post: '/community/clubs', fixtures: '/fixtures', watch: '/market', appearances: '/squad', high_score: '/squad', sell: '/portfolio', community: '/community/clubs', price: '/market' };
export function weekDays(week: string) {
 if (!week) return [];
 const start = new Date(week + 'T00:00:00Z');
 return Array.from({ length: 7 }, (_, i) => new Date(start.getTime() + i * 86400000).toISOString().slice(0, 10));
}
export function cosmeticTheme(id?: string | null) { return id?.replace(/^(nameplate|frame|pitch)-/, '') ?? 'default'; }
