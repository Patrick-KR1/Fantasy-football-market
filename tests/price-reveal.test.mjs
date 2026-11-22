import test from 'node:test';
import assert from 'node:assert/strict';
import { loadTs } from './load-ts.mjs';
const { priceRevealPlayers, priceRevealPage, priceRevealSignature } = loadTs('../lib/kickx/price-reveal.ts');
const player = (id, change, price = 100000) => ({ id, name: id, price, change });

for (const [count, sizes] of [[0, []], [1, [1]], [6, [6]], [7, [6, 1]], [12, [6, 6]], [13, [6, 6, 1]]]) {
  test(`${count} owned players paginate without omission or duplication`, () => {
    const players = Array.from({ length: count }, (_, i) => player(`p${i}`, i + 1));
    const pages = sizes.map((_, page) => priceRevealPage(players, page));
    assert.deepEqual(pages.map(page => page.length), sizes);
    assert.deepEqual(pages.flat(), players);
    assert.deepEqual(priceRevealPage(players, sizes.length), []);
  });
}

test('automatic reveal selects only unseen finite movements from owned players, largest first', () => {
  const players = [player('up', 3), player('down', -8), player('seen', 10), player('flat', 0), player('unknown', null), player('invalid', NaN), player('unpriced', 5, null), player('infinite', 5, Infinity), player('unowned', 99)];
  const get = id => players.find(p => p.id === id);
  const ids = players.filter(p => p.id !== 'unowned').map(p => p.id);
  const seen = { seen: priceRevealSignature(get('seen')) };
  assert.deepEqual(priceRevealPlayers([...ids, 'up', 'missing'], get, seen).map(p => p.id), ['down', 'up']);
  assert.deepEqual(seen, { seen: '100000|10' });
});

test('replay includes seen, unchanged and unpriced holdings but never unowned or duplicate players', () => {
  const players = [player('starter', 3), player('bench', -8), player('flat', 0), player('unknown', null), player('unpriced', 1, null), player('unowned', 99)];
  const get = id => players.find(p => p.id === id);
  const seen = { starter: priceRevealSignature(get('starter')), bench: priceRevealSignature(get('bench')) };
  const before = JSON.stringify({ players, seen });
  assert.deepEqual(priceRevealPlayers(['starter', 'bench', 'flat', 'unknown', 'unpriced', 'bench', 'missing'], get, seen, true).map(p => p.id), ['bench', 'starter', 'unpriced', 'flat', 'unknown']);
  assert.equal(JSON.stringify({ players, seen }), before);
});

test('a newer server value is eligible again even for a previously seen player', () => {
  const current = player('p', -5, 95000);
  assert.equal(priceRevealPlayers(['p'], () => current, { p: '100000|3' }).length, 1);
  assert.equal(priceRevealPlayers(['p'], () => current, { p: priceRevealSignature(current) }).length, 0);
});
