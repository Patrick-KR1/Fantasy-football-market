import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { mkdir, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { loadTs } from './load-ts.mjs';
const { chromium } = await import(pathToFileURL(resolve(process.env.KICKX_BROWSER_MODULE || '/tmp/kickx-browser', 'node_modules/playwright/index.mjs')).href);
const { emptyPlatformData } = loadTs('../lib/kickx/data.ts');
const { FORMATIONS } = loadTs('../lib/kickx/squad.ts');
const base = 'http://localhost:3117', out = 'test-artifacts/price-reveal';
const server = spawn(process.execPath, ['node_modules/next/dist/bin/next', 'start', '-H', 'localhost', '-p', '3117'], { stdio: 'ignore' });
const report = { flows: [], layouts: [], errors: [] };
const seenKey = 'kickx:price-seen:reveal-member';
let browser;
try {
  for (let i = 0; i < 40; i++) {
    try { if ((await fetch(base)).ok) break; } catch {}
    if (i === 39) throw Error('App did not start');
    await new Promise(resolve => setTimeout(resolve, 500));
  }
  browser = await chromium.launch({ executablePath: process.env.KICKX_BROWSER_EXECUTABLE || undefined });
  await mkdir(out, { recursive: true });
  for (const width of [1440, 390, 320]) {
    const height = width === 1440 ? 900 : 844;
    const players = Array.from({ length: 13 }, (_, i) => ({
      id: `reveal-${i}`, name: `테스트 선수 ${i + 1}`, short: `선수${i + 1}`,
      position: FORMATIONS[0].positions[i % 11], price: 100000 + i * 2000,
      change: (i + 1) * (i % 2 ? -1 : 1), team: 'club', history: [], records: [], analysis: null,
    }));
    const holdings = players.map((p, i) => ({ id: p.id, playerId: p.id, playerName: p.name, cost: 100000, value: p.price, quantity: 1,
      ...(i >= 11 ? { bench: { price: p.price, reason: 'formation', startedAt: new Date().toISOString(), expiresAt: new Date(Date.now() + 7 * 86400000).toISOString() } } : {}),
    }));
    const state = { ...emptyPlatformData(), players, formations: FORMATIONS,
      teams: [{ id: 'club', name: '테스트 구단', leagueId: 'bsd-1' }], leagues: [{ id: 'bsd-1', name: 'Premier League' }],
      session: { userId: 'reveal-member', role: 'member', profile: { nickname: '연출 확인', team: 'club', teams: ['club'], primaryTeam: 'club' } },
      member: { financialReady: true, points: 700000, totalAssets: 2000000, playerAssets: 1300000, holdings, ownedPlayers: players, transactions: [], watchlist: [], assetHistory: [],
        squad: { formationId: '4-3-3', slots: players.slice(0, 11).map(p => p.id), revision: 1, value: 1100000, performance: 8 } },
    };
    const context = await browser.newContext({ viewport: { width, height }, timezoneId: 'Asia/Seoul', reducedMotion: 'reduce' });
    await context.route(/^https:\/\//, route => route.abort());
    let mutations = 0;
    await context.route('**/api/**', route => {
      const req = route.request(), path = new URL(req.url()).pathname;
      const ready = data => route.fulfill({ json: { status: 'ready', source: 'database', data } });
      if (req.method() !== 'GET' && path !== '/api/kickx/engagement') mutations++;
      if (path === '/api/kickx') return ready(state);
      if (path === '/api/kickx/notifications') return ready({ hasUnread: false, matchNotifications: true });
      if (path === '/api/kickx/players') return ready({ items: players, total: players.length, page: 1, size: 8 });
      if (path === '/api/kickx/engagement') return ready({ loadout: { frame: 'frame-dragon' } });
      return ready({ items: [], total: 0, page: 1, size: 20 });
    });
    const page = await context.newPage();
    page.on('pageerror', error => report.errors.push(error.message));
    await page.goto(base + '/squad', { waitUntil: 'domcontentloaded' });
    const dialog = page.getByRole('dialog', { name: /가격 변동 확인/ });
    await dialog.waitFor();
    const actual = [];
    for (const [index, size] of [6, 6, 1].entries()) {
      await page.waitForFunction(size => document.querySelectorAll('.price-reveal-card').length === size, size);
      assert.equal(await dialog.locator('.price-reveal-card').count(), size);
      assert.match(await dialog.locator('.price-reveal-pagination').innerText(), new RegExp(`${index + 1} / 3`));
      actual.push(...await dialog.locator('.price-reveal-card').evaluateAll(cards => cards.map(card => card.dataset.playerId)));
      if (index === 0) {
        assert.equal(await dialog.locator('.is-up').count(), 3);
        assert.equal(await dialog.locator('.is-down').count(), 3);
        assert.equal(await page.evaluate(() => document.body.style.overflow), 'hidden');
        const layout = await dialog.evaluate(el => {
          const actions = el.querySelector('.price-reveal-actions').getBoundingClientRect();
          const grid = el.querySelector('.price-reveal-grid');
          const columns = getComputedStyle(grid).gridTemplateColumns.split(' ').length;
          return { columns, width: innerWidth, documentWidth: document.documentElement.scrollWidth, gridWidth: grid.clientWidth, gridScrollWidth: grid.scrollWidth, footerBottom: actions.bottom, height: innerHeight };
        });
        assert.equal(layout.columns, width > 640 ? 3 : 2);
        assert(layout.documentWidth <= layout.width + 1);
        assert(layout.gridScrollWidth <= layout.gridWidth + 1);
        assert(layout.footerBottom <= layout.height);
        report.layouts.push({ width, ...layout });
        await page.screenshot({ path: `${out}/six-players-${width}.png` });
      }
      await dialog.getByRole('button', { name: index === 2 ? '확인' : '다음 페이지', exact: true }).click();
    }
    await dialog.waitFor({ state: 'detached' });
    assert.equal(new Set(actual).size, 13);
    assert.deepEqual(actual, players.slice().sort((a, b) => Math.abs(b.change) - Math.abs(a.change)).map(p => p.id));
    const seen = await page.evaluate(key => localStorage.getItem(key), seenKey);
    assert.equal(Object.keys(JSON.parse(seen)).length, 13);
    assert.equal(await page.evaluate(() => document.body.style.overflow), '');
    // Automatic opt-out and seen history must not block the explicit replay button.
    await page.evaluate(() => localStorage.setItem('kickx:price-reveal', 'off'));
    const replay = page.locator('.squad-team').getByRole('button', { name: '마지막 변동 확인', exact: true });
    await replay.click();
    const preview = page.getByRole('dialog', { name: /마지막 변동 확인/ });
    await preview.waitFor();
    assert.equal(await preview.locator('.price-reveal-card').count(), 6);
    assert.match(await preview.innerText(), /1–6 \/ 13명/);
    assert.match(await preview.innerText(), /테스트 선수 13/); // Bench holdings are included.
    await page.keyboard.press('Tab');
    assert.equal(await page.evaluate(() => document.activeElement?.textContent), '닫기');
    await page.keyboard.press('Shift+Tab');
    assert.match(await page.evaluate(() => document.activeElement?.textContent), /다음 페이지/);
    await preview.getByRole('button', { name: '다음 페이지', exact: true }).click();
    await page.keyboard.press('Escape');
    await preview.waitFor({ state: 'detached' });
    assert.equal(await page.evaluate(key => localStorage.getItem(key), seenKey), seen);
    assert(await replay.evaluate(el => document.activeElement === el));
    await replay.click(); // Repeated tests remain available.
    await preview.waitFor();
    assert.match(await preview.innerText(), /1–6 \/ 13명/);
    await preview.getByRole('button', { name: '닫기', exact: true }).click();
    // No movement / missing movement must not be labelled as a fall in replay.
    players[12].change = 0;
    players[11].change = null;
    await page.reload({ waitUntil: 'domcontentloaded' });
    await replay.waitFor();
    await replay.click();
    await preview.waitFor();
    await preview.getByRole('button', { name: '다음 페이지', exact: true }).click();
    assert.match(await preview.locator('.price-reveal-card.is-flat').innerText(), /변동 정보 없음/);
    await preview.getByRole('button', { name: '다음 페이지', exact: true }).click();
    assert.match(await preview.locator('.price-reveal-card').innerText(), /변동 없음/);
    assert.equal(await preview.locator('.price-reveal-card.is-flat').count(), 1);
    assert.equal(await preview.locator('.price-reveal-arrows').count(), 0);
    await preview.getByRole('button', { name: '확인', exact: true }).click();
    assert.equal(mutations, 0, 'Reveal and replay do not mutate football or financial data');
    report.flows.push({ width, pages: [6, 6, 1], replayWithoutSeenWrites: true, benchIncluded: true });
    await context.close();
  }
  assert.deepEqual(report.errors, []);
  console.log(JSON.stringify(report));
} finally {
  await mkdir(out, { recursive: true });
  await writeFile(`${out}/report.json`, JSON.stringify(report, null, 2));
  await browser?.close();
  server.kill('SIGTERM');
}
