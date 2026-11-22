import type { Player } from "./types";

export const PRICE_REVEAL_PAGE_SIZE = 6;

export const priceRevealSignature = (player: Player) =>
  `${player.price}|${player.change}`;

/** Use server values, including bench players; replay never invents a price move. */
export function priceRevealPlayers(
  playerIds: string[],
  getPlayer: (id: string) => Player | undefined,
  seen: Record<string, string> = {},
  preview = false,
): Player[] {
  return [...new Set(playerIds)]
    .map(getPlayer)
    .filter((player): player is Player => {
      if (!player) return false;
      if (preview) return true;
      return (
        player.price != null &&
        Number.isFinite(player.price) &&
        player.change != null &&
        Number.isFinite(player.change) &&
        player.change !== 0 &&
        seen[player.id] !== priceRevealSignature(player)
      );
    })
    .sort((a, b) => {
      const magnitude = (player: Player) =>
        Number.isFinite(player.change) ? Math.abs(player.change ?? 0) : 0;
      return magnitude(b) - magnitude(a);
    });
}

export function priceRevealPage(players: Player[], pageIndex: number) {
  const start = pageIndex * PRICE_REVEAL_PAGE_SIZE;
  return players.slice(start, start + PRICE_REVEAL_PAGE_SIZE);
}
