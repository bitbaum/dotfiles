#!/usr/bin/env node
/**
 * Self-test for model-pin-audit.mjs.
 * Run: node scripts/ci/test-model-pin-audit.mjs
 *
 * A detector that has quietly stopped detecting reports a clean fleet, and a
 * clean report from a broken detector is worse than no report — it is an absent
 * check that prints a ✓. So every fixture asserts a VERDICT, and both sides are
 * pinned:
 *
 *   - the real AOZ regression is still caught      (positive)
 *   - the corrected file stays silent              (negative)
 *   - quoted things that are not model ids stay out of the report
 *   - an unreadable catalogue reports UNCHECKED, never GONE
 *
 * That last one is the expensive mistake. Treating "I could not look" as
 * "nothing is there" marks every pin retired and invents a fleet-wide outage
 * that somebody will act on. Silence is recoverable; a false alarm at this
 * scale is not.
 *
 * Fixtures are inline strings — no network, no gh, no checkout, no key.
 */
import { extractPins, attribute, collate, judge, looksLikeModelId } from "./model-pin-audit.mjs";

let failures = 0;
function check(name, actual, expected) {
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  if (a === e) {
    console.log(`  ok   ${name}`);
  } else {
    console.log(`  FAIL ${name}\n         expected ${e}\n         actual   ${a}`);
    failures++;
  }
}

// ── Fixtures ─────────────────────────────────────────────────────────────────

/** aoz-housing/src/lib/env.ts as it stood when both AI surfaces went down. */
const AOZ_BROKEN = `
import { z } from 'zod'

const schema = z.object({
  DATABASE_URL: z.string().url(),
  CRON_SECRET: z.string().min(16).optional(),

  // AI: whichever key is set decides the provider.
  GROQ_API_KEY: z.string().optional(),
  GROQ_MODEL: z.string().default('llama-3.3-70b-versatile'),
  OPENROUTER_API_KEY: z.string().optional(),
  OPENROUTER_MODEL: z.string().default('openai/gpt-oss-20b:free'),
})
`;

/** The same file after the fix. Must produce no findings at all. */
const AOZ_FIXED = AOZ_BROKEN.replace("llama-3.3-70b-versatile", "openai/gpt-oss-120b");

/** aoz-housing/src/lib/ai/provider.ts — one module, BOTH vendors named. */
const TWO_VENDOR_FILE = `
const GROQ_API_URL = 'https://api.groq.com/openai/v1/chat/completions'
const OPENROUTER_API_URL = 'https://openrouter.ai/api/v1/chat/completions'

export async function getConfig() {
  if (provider === 'groq') {
    return { url: GROQ_API_URL, model: 'llama-3.1-8b-instant' }
  }
  return { url: OPENROUTER_API_URL, model: 'meta-llama/llama-3.3-70b-instruct:free' }
}
`;

/** Quoted strings that must never be mistaken for model ids. */
const NOISE = `
import { BRAND } from '@/lib/config/brand'
const path = './lib/ai/provider.ts'
const url = 'https://api.groq.com/openai/v1/chat/completions'
const key = 'GROQ_API_KEY'
const model = 'llama-3.1-8b-instant'
const style = 'rounded-lg'
`;

// ── looksLikeModelId ─────────────────────────────────────────────────────────

console.log("looksLikeModelId");
check("accepts a versioned id", looksLikeModelId("llama-3.3-70b-versatile"), true);
check("accepts a routed id", looksLikeModelId("openai/gpt-oss-20b:free"), true);
check("rejects a relative path", looksLikeModelId("./lib/ai/provider.ts"), false);
check("rejects a url", looksLikeModelId("https://api.groq.com/openai/v1"), false);
check("rejects an env var name", looksLikeModelId("GROQ_API_KEY"), false);
check("rejects a css class", looksLikeModelId("rounded-lg"), false);
check("rejects a module specifier", looksLikeModelId("@/lib/config/brand"), false);
// fleetcrown builds its model id from ai-ration's chain at call time. A
// computed id is the ABSENCE of a pin, and the first run reported it retired.
check("rejects an interpolated id", looksLikeModelId("${link.provider.id}/${link.model}"), false);

// ── extraction ───────────────────────────────────────────────────────────────

console.log("\nextractPins");
check(
  "finds both pins in the broken AOZ env schema",
  extractPins(AOZ_BROKEN).map((p) => p.id).sort(),
  ["llama-3.3-70b-versatile", "openai/gpt-oss-20b:free"],
);
check(
  "finds the model literals in a two-vendor provider",
  extractPins(TWO_VENDOR_FILE).map((p) => p.id).sort(),
  ["llama-3.1-8b-instant", "meta-llama/llama-3.3-70b-instruct:free"],
);
check(
  "picks the model id out of a file full of other quoted strings",
  extractPins(NOISE).map((p) => p.id),
  ["llama-3.1-8b-instant"],
);

// ── attribution ──────────────────────────────────────────────────────────────

console.log("\nattribute");
{
  const pins = extractPins(AOZ_BROKEN);
  const groq = pins.find((p) => p.id === "llama-3.3-70b-versatile");
  const or = pins.find((p) => p.id === "openai/gpt-oss-20b:free");
  check("GROQ_MODEL line attributes to groq", attribute(AOZ_BROKEN, groq.line), "groq");
  check("OPENROUTER_MODEL line attributes to openrouter", attribute(AOZ_BROKEN, or.line), "openrouter");
}
{
  // The case a file-wide vote gets wrong: both vendors named in one module, so
  // only the pin's own neighbourhood says which branch it belongs to.
  const pins = extractPins(TWO_VENDOR_FILE);
  const g = pins.find((p) => p.id === "llama-3.1-8b-instant");
  const o = pins.find((p) => p.id === "meta-llama/llama-3.3-70b-instruct:free");
  check("nearest marker wins for the groq branch", attribute(TWO_VENDOR_FILE, g.line), "groq");
  check("nearest marker wins for the openrouter branch", attribute(TWO_VENDOR_FILE, o.line), "openrouter");
}
check(
  "a pin with no vendor anywhere is not attributed",
  attribute("const model = 'some-model-9b'", 1),
  null,
);

// ── judging ──────────────────────────────────────────────────────────────────

console.log("\njudge");
const findingsFrom = (repo, path, text) =>
  extractPins(text).map((p) => ({
    repo,
    path,
    line: p.line,
    id: p.id,
    vendor: attribute(text, p.line),
  }));

const GROQ_LIVE = new Set(["openai/gpt-oss-120b", "openai/gpt-oss-20b", "qwen/qwen3.8-27b"]);
const OR_LIVE = new Set(["openai/gpt-oss-20b:free"]);

{
  const findings = findingsFrom("aoz-housing", "src/lib/env.ts", AOZ_BROKEN);
  const live = new Map([["groq", GROQ_LIVE], ["openrouter", OR_LIVE]]);
  const judged = judge(findings, live);

  check(
    "THE REGRESSION: the retired llama pin is caught",
    judged.filter((j) => j.state === "gone").map((j) => j.id),
    ["llama-3.3-70b-versatile"],
  );
  check(
    "the still-served openrouter pin beside it stays quiet",
    judged.filter((j) => j.state === "ok").map((j) => j.id),
    ["openai/gpt-oss-20b:free"],
  );
}

{
  // The negative that matters most: correct code must produce a silent report,
  // or the audit trains people to ignore it.
  const findings = findingsFrom("aoz-housing", "src/lib/env.ts", AOZ_FIXED);
  const live = new Map([["groq", GROQ_LIVE], ["openrouter", OR_LIVE]]);
  const judged = judge(findings, live);
  check("the FIXED file reports nothing retired", judged.filter((j) => j.state === "gone"), []);
  check("and confirms both pins live", judged.filter((j) => j.state === "ok").length, 2);
}

{
  // An unreadable catalogue must never read as rot. This is the guard against
  // a missing key printing a fleet-wide outage that somebody then acts on.
  const findings = findingsFrom("aoz-housing", "src/lib/env.ts", AOZ_BROKEN);
  const live = new Map([["groq", null], ["openrouter", null]]);
  const judged = judge(findings, live);
  check("no key => UNCHECKED, never GONE", judged.filter((j) => j.state === "gone"), []);
  check("and every pin is reported unchecked", judged.filter((j) => j.state === "unchecked").length, 2);
}

{
  const findings = [{ repo: "x", path: "y", line: 1, id: "some-model-9b", vendor: null }];
  const judged = judge(findings, new Map());
  check("an unattributed pin is listed, not judged", judged[0].state, "unattributed");
}

// ── collate ──────────────────────────────────────────────────────────────────

console.log("\ncollate");
{
  const findings = [
    ...findingsFrom("a", "env.ts", AOZ_BROKEN),
    { repo: "b", path: "c.ts", line: 1, id: "mystery-1b", vendor: null },
  ];
  const { byVendor, unattributed } = collate(findings);
  check("groups by vendor", [...byVendor.keys()].sort(), ["groq", "openrouter"]);
  check("keeps the unattributable aside", unattributed.map((u) => u.id), ["mystery-1b"]);
}

// ── vendor confusion ─────────────────────────────────────────────────────────
//
// Found by running the audit for the first time, so it is pinned here.
//
// kivvi/apps/web/lib/ai/call-provider.ts dispatches four vendors in one
// function. `grok-3-mini` is xAI's model; Groq is a different company whose
// name differs by one letter, and whose base URL sat 18 lines above the pin
// while xAI's sat 6 above. Ranking by raw proximity called a live xAI model a
// retired Groq one — and the Groq pin six lines up tied EXACTLY between the two
// vendors, so a tie-break by proximity alone lost a true positive as well.
//
// Both halves are asserted: the xAI id must not be judged against Groq's
// catalogue, and the real Groq pin must still be caught.
const KIVVI_MULTI_VENDOR = `
export async function callProvider(provider, apiKey, systemPrompt, userText, maxTokens) {
  let url;
  let headers;
  let body;

  if (provider === "groq") {
    url = "https://api.groq.com/openai/v1/chat/completions";
    headers = { Authorization: \`Bearer \${apiKey}\` };
    body = {
      model: "llama-3.1-8b-instant",
      messages: openaiMessages,
    };
  } else if (provider === "xai") {
    url = "https://api.x.ai/v1/chat/completions";
    headers = { Authorization: \`Bearer \${apiKey}\` };
    body = {
      model: "grok-3-mini",
      messages: openaiMessages,
    };
  }
}
`;

console.log("\nvendor confusion (regression)");
{
  const pins = extractPins(KIVVI_MULTI_VENDOR);
  const groqPin = pins.find((p) => p.id === "llama-3.1-8b-instant");
  const xaiPin = pins.find((p) => p.id === "grok-3-mini");

  check("both vendor pins are extracted", Boolean(groqPin && xaiPin), true);
  check("xAI's grok-3-mini is NOT attributed to groq", attribute(KIVVI_MULTI_VENDOR, xaiPin.line), "xai");
  check("the groq pin above it still attributes to groq", attribute(KIVVI_MULTI_VENDOR, groqPin.line), "groq");

  // Only groq is queryable, so the xAI id must land in unchecked — never judged
  // against a catalogue that was never going to list it.
  const findings = pins.map((p) => ({
    repo: "kivvi",
    path: "apps/web/lib/ai/call-provider.ts",
    line: p.line,
    id: p.id,
    vendor: attribute(KIVVI_MULTI_VENDOR, p.line),
  }));
  const judged = judge(findings, new Map([["groq", GROQ_LIVE]]));
  check("the real groq pin is still caught as retired", judged.filter((j) => j.state === "gone").map((j) => j.id), ["llama-3.1-8b-instant"]);
  check("the xAI pin is unchecked, not retired", judged.filter((j) => j.state === "unchecked").map((j) => j.id), ["grok-3-mini"]);
}

console.log(failures ? `\n✗ ${failures} failure(s)` : "\n✓ all checks pass");
process.exit(failures ? 1 : 0);
