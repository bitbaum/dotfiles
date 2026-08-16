#!/usr/bin/env node
/**
 * Self-test for ui-defect-audit.mjs.
 * Run: node scripts/ci/test-ui-defect-audit.mjs
 *
 * A detector is only worth its output if BOTH sides are pinned. The first draft
 * of this audit flagged 88 "defects" across 14 sites, and most of the alignment
 * ones were a heading followed by consistently indented items — correct markup
 * reported as broken. A rule that fires on everything is as useless as one that
 * fires on nothing, and it is more expensive, because someone has to read it.
 *
 * So every fixture below asserts a VERDICT, not just a run:
 *   - the real fleetcrown bug is still caught (positive)
 *   - correct markup stays silent (negative)
 *
 * Fixtures are inline data: URLs — no network, no fleet, no auth.
 */
import { loadPlaywright, MEASURE } from "./ui-defect-audit.mjs";

const FIXTURES = {
  // The original fleetcrown fleet card: an icon INLINE at the head of two of
  // the four rows, shoving only those lines sideways by its own width, and a
  // wrapped hint whose second line falls back to the container edge.
  raggedStack: `
    <div style="background:#070707;color:#e4e4e4;font:14px sans-serif;padding:24px">
      <div style="display:flex;flex-direction:column;gap:4px;width:600px">
        <p style="margin:0">Fleet autopilot</p>
        <p style="margin:0"><span aria-hidden="true" style="display:inline-block;width:6px;height:6px;background:#4ade80;border-radius:9999px"></span> Idle — nothing queued</p>
        <div style="display:flex;gap:8px"><span>0 working</span><span>21 idle</span></div>
        <p style="margin:0"><svg aria-hidden="true" width="12" height="12" style="display:inline"></svg> Autopilot on — agents work through each project's queue, then pick the next-best task automatically and keep going until the queue is empty.</p>
      </div>
    </div>`,

  // The SAME visual family done correctly: icons hang in a fixed gutter, every
  // row shares one text column, the wrapped line has a hanging indent.
  fixedStack: `
    <div style="background:#070707;color:#e4e4e4;font:14px sans-serif;padding:24px">
      <div style="display:flex;flex-direction:column;gap:4px;width:600px">
        <p style="margin:0;padding-left:20px">Fleet autopilot</p>
        <p style="margin:0;padding-left:20px;text-indent:-20px"><span aria-hidden="true" style="display:inline-block;width:20px;height:6px"></span>Idle — nothing queued</p>
        <div style="display:flex;gap:8px;padding-left:20px"><span>0 working</span><span>21 idle</span></div>
        <p style="margin:0;padding-left:20px;text-indent:-20px"><span aria-hidden="true" style="display:inline-block;width:20px;height:12px"></span>Autopilot on — agents work through each project's queue, then pick the next-best task automatically and keep going until the queue is empty.</p>
      </div>
    </div>`,

  // Correct markup that the first draft wrongly flagged: a label, then items
  // deliberately indented under it. The column goes out once and STAYS — no
  // return to a previous edge, so it is structure, not raggedness.
  intentionalIndent: `
    <div style="background:#070707;color:#e4e4e4;font:14px sans-serif;padding:24px">
      <div style="display:flex;flex-direction:column;gap:4px;width:600px">
        <p style="margin:0">GUT · BRAIN AXIS</p>
        <p style="margin:0;padding-left:13px">Vollständige Mikrobiomanalyse</p>
        <p style="margin:0;padding-left:13px">Darmpermeabilitätsmarker</p>
        <p style="margin:0;padding-left:13px">Neurotransmitter-Vorläuferstatus</p>
      </div>
    </div>`,

  // An action below the AA floor, and one comfortably above it.
  contrast: `
    <div style="background:#030303;font:12px sans-serif;padding:24px">
      <a href="#dim" style="color:#5d5d5d">Full inbox — screenshots, history, widget setup</a>
      <br>
      <a href="#ok" style="color:#8f8f8f">New feedback</a>
    </div>`,

  // Chips on a 4%-white overlay over near-black. A naive single canvas paint
  // resolves that overlay to SOLID WHITE and reports these as failures.
  translucentChips: `
    <div style="background:#030303;font:12px sans-serif;padding:24px">
      <button style="color:#e4e4e4;background:oklch(1 0 0 / 0.04);border:0;padding:4px 10px">0 working</button>
      <button style="color:#e4e4e4;background:oklch(1 0 0 / 0.04);border:0;padding:4px 10px">21 idle</button>
    </div>`,
};

function assert(cond, msg) {
  if (!cond) throw new Error(msg);
}

async function main() {
  const { chromium } = loadPlaywright();
  const browser = await chromium.launch();
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 } });
  const page = await ctx.newPage();

  const measure = async (html) => {
    await page.setContent(`<!doctype html><meta charset="utf-8">${html}`, { waitUntil: "load" });
    await page.waitForTimeout(120);
    return page.evaluate(MEASURE);
  };

  let passed = 0;
  const check = async (label, fn) => {
    await fn();
    passed += 1;
    console.log(`  ✓ ${label}`);
  };

  await check("catches the ragged stack it was written for", async () => {
    const r = await measure(FIXTURES.raggedStack);
    assert(r.ragged.length >= 1, "the zigzag stack must be reported");
    assert(
      r.ragged.some((g) => g.spread >= 4 && g.spread <= 24),
      `spread must land in the accidental-indent band, got ${JSON.stringify(r.ragged.map((g) => g.spread))}`,
    );
  });

  await check("catches the wrapped line with no hanging indent", async () => {
    const r = await measure(FIXTURES.raggedStack);
    assert(r.wrapped.length >= 1, "line 2 starting left of line 1 must be reported");
  });

  await check("stays silent once the gutter fix is applied", async () => {
    const r = await measure(FIXTURES.fixedStack);
    assert(r.ragged.length === 0, `fixed stack must be clean, got ${JSON.stringify(r.ragged)}`);
    assert(r.wrapped.length === 0, `hanging indent must be clean, got ${JSON.stringify(r.wrapped)}`);
  });

  await check("does NOT flag a label with deliberately indented items", async () => {
    const r = await measure(FIXTURES.intentionalIndent);
    assert(
      r.ragged.length === 0,
      `structure must not read as raggedness, got ${JSON.stringify(r.ragged)}`,
    );
  });

  await check("reports a sub-AA action and spares a passing one", async () => {
    const r = await measure(FIXTURES.contrast);
    const dim = r.contrast.find((c) => c.href === "#dim");
    const ok = r.contrast.find((c) => c.href === "#ok");
    assert(dim && dim.value < dim.floor, `dim link must fail, got ${dim && dim.value}`);
    assert(ok && ok.value >= ok.floor, `readable link must pass, got ${ok && ok.value}`);
  });

  await check("composites translucent chips instead of calling them white", async () => {
    const r = await measure(FIXTURES.translucentChips);
    const chips = r.contrast.filter((c) => /working|idle/.test(c.text));
    assert(chips.length === 2, `expected 2 chips, got ${chips.length}`);
    for (const c of chips) {
      assert(
        c.value >= c.floor,
        `light text on a 4%-white overlay over near-black is readable; got ${c.value}:1 ` +
        `(a single canvas paint reports ~3.2 here)`,
      );
    }
  });

  await browser.close();
  console.log(`\n${passed}/${passed} ui-defect-audit self-tests passed`);
}

main().catch((e) => {
  console.error(`\n✗ ${e.message}`);
  process.exit(1);
});
