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
import {
  extractPins,
  attribute,
  collate,
  judge,
  looksLikeModelId,
  possibleAt,
  isLikelyPath,
  isPossiblePath,
  isCandidatePath,
  segmentNamesAI,
  modelListRegions,
} from "./model-pin-audit.mjs";

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

// ── a display label is not a pin ────────────────────────────────────
//
// Regression: the audit announced a RETIRED model in OrangeCat, a repo with
// nothing wrong. The string was marketing copy in a pricing table — every other
// entry contained a space and was filtered out, `GPT-4o` did not. Reporting a
// healthy repo as broken is how a daily gate loses its reader.
//
// Both halves are asserted. Suppressing the false one is only worth doing if
// the real retired pin in the very same file is still caught.

console.log("\ndisplay labels vs real pins");

const ORANGECAT_UI = `
import { OPENROUTER_API_URL } from './constants'

export const TIERS = {
  standard: {
    title: 'Standard Tier',
    models: ['Claude 3.5 Sonnet', 'GPT-4o', 'Gemini 2.0 Flash'],
  },
}

// the actual call, further down the same file
const model = 'openai/gpt-oss-20b:free'
`;

{
  check("an uppercase id is impossible at openrouter", possibleAt("openrouter", "GPT-4o"), false);
  check("and impossible at groq", possibleAt("groq", "Llama-3.3-70B"), false);
  check("but lowercase ids stay possible", possibleAt("openrouter", "openai/gpt-oss-20b:free"), true);
  // Uppercase is only impossible where the catalogue was measured. Together's
  // real ids DO carry capitals, so the rule must not spread to every vendor.
  check("uppercase is not ruled out at vendors we did not measure", possibleAt("together", "meta-llama/Llama-3.3-70B-Instruct-Turbo-Free"), true);

  const pins = extractPins(ORANGECAT_UI);
  const findings = pins.map((p) => ({
    repo: "orangecat",
    path: "src/lib/ai-guidance.ts",
    line: p.line,
    id: p.id,
    vendor: attribute(ORANGECAT_UI, p.line),
  }));
  const judged = judge(findings, new Map([["openrouter", OR_LIVE]]));

  check(
    "the display label is not reported as retired",
    judged.filter((j) => j.state === "gone").map((j) => j.id).includes("GPT-4o"),
    false,
  );
  check(
    "it is listed as unjudged rather than dropped",
    judged.filter((j) => j.state === "unattributed").map((j) => j.id).includes("GPT-4o"),
    true,
  );
  // OR_LIVE contains openai/gpt-oss-20b:free, so the real pin here is live —
  // what matters is that it was judged at all, not silenced alongside the label.
  check(
    "the real pin in the same file is still judged against the catalogue",
    judged.find((j) => j.id === "openai/gpt-oss-20b:free")?.state,
    "ok",
  );
}

// ── which files get opened ───────────────────────────────────────────
//
// Regression, and the expensive kind: a MISS, not a false alarm.
//
// The filter used to require the AI word in the FILENAME. Kivvi keeps its
// provider clients side by side in packages/ai/src/providers/, and the audit
// opened `anthropic.ts` while never opening `groq.ts` next to it — decided
// entirely by which vendor names happened to be in a regex. Three retired ids
// sat in the unopened files, so the report said Kivvi had 2 dead pins when it
// had 6.
//
// Understating a repo is worse than skipping it. A skipped repo is absent; an
// understated one prints a number that reads like an answer.

console.log("\nwhich files get opened");

{
  // The four files from the miss, verbatim.
  check("a vendor-named file under an ai/ directory is likely", isLikelyPath("packages/ai/src/providers/groq.ts"), true);
  check("...and so is its openrouter sibling", isLikelyPath("packages/ai/src/providers/openrouter.ts"), true);
  check("...and the index.ts beside them", isLikelyPath("packages/ai/src/providers/index.ts"), true);
  check("...and the one that already worked still works", isLikelyPath("packages/ai/src/providers/anthropic.ts"), true);

  check("the app-side caller stays likely", isLikelyPath("apps/web/lib/ai/call-provider.ts"), true);
  check("env schemas are always opened", isLikelyPath("src/lib/env.ts"), true);
  check("so are .env.example files", isLikelyPath(".env.example"), true);

  // Botsmann's pin lived here, in a path naming no vendor and no AI concern.
  check("a bare constants file is not likely", isLikelyPath("lib/constants.ts"), false);
  check("...but is still a candidate, via the possible tier", isPossiblePath("lib/constants.ts"), true);
  check("...so it does get opened", isCandidatePath("lib/constants.ts"), true);
}

// Matching is by token, never substring — this is the half that keeps the fix
// from turning one blind spot into a flood. `ai` is a substring of all of these,
// and the cap would then drop real candidates to make room for them.
{
  check("mail is not ai", segmentNamesAI("mail.ts"), false);
  check("domain is not ai", segmentNamesAI("domain.ts"), false);
  check("detail is not ai", segmentNamesAI("detail.ts"), false);
  check("maintenance is not ai", segmentNamesAI("maintenance.ts"), false);
  check("captain is not ai", segmentNamesAI("captain.ts"), false);

  check("but ai is ai", segmentNamesAI("ai"), true);
  check("and ai-guidance is ai", segmentNamesAI("ai-guidance.ts"), true);
  check("and call-provider is a provider", segmentNamesAI("call-provider.ts"), true);
  check("and llm-client is an llm", segmentNamesAI("llm-client.ts"), true);

  check("an unrelated util is not opened", isCandidatePath("src/lib/format-date.ts"), false);
  check("nor is a mailer", isCandidatePath("src/lib/mail.ts"), false);
}

// ── model arrays the old regex could not read ─────────────────────────────
//
// Second half of the Kivvi miss. Even once the file was being opened, nothing
// came out of it: the extractor matched `models` followed directly by `[`, and
// Kivvi writes a TypeScript type annotation in between.
//
//     models: AIModel[] = [
//
// The first `[` on that line belongs to `AIModel[]` and closes immediately, so
// anchoring to it reads an empty array — a silent nothing, which is the worst
// possible output for an audit. Two retired Groq ids sat inside.

console.log("\nmodel arrays");

const KIVVI_TYPED_ARRAY = `
import type { AIModel } from "../types";

/** Uses OpenAI-compatible API at https://api.groq.com/openai/v1. */
export class GroqProvider extends OpenAICompatibleProvider {
  id = "groq";
  name = "Groq";

  models: AIModel[] = [
    {
      id: "llama-3.3-70b-versatile",
      name: "Llama 3.3 70B",
      contextWindow: 128000,
      supportsTools: true,
      costPer1kInput: 0,
    },
    {
      id: "llama-3.1-8b-instant",
      name: "Llama 3.1 8B Instant",
      contextWindow: 128000,
      supportsTools: true,
      costPer1kInput: 0,
    },
  ];

  protected baseUrl = "https://api.groq.com/openai/v1";
}
`;

{
  const pins = extractPins(KIVVI_TYPED_ARRAY);
  const ids = pins.map((p) => p.id).sort();
  check(
    "a type-annotated models array is read at all",
    ids,
    ["llama-3.1-8b-instant", "llama-3.3-70b-versatile"],
  );

  // The SECOND entry is the one a fixed-width window loses. The old pattern
  // read at most 400 characters after `models`, and a richly described list
  // runs past that long before it ends.
  check("the second entry is not lost to a character budget", ids.length, 2);

  // Human-readable names sit in the same objects and must not be mistaken for
  // ids — they are filtered by shape, not by position.
  check("display names in the same object are not pins", ids.includes("Llama 3.3 70B"), false);

  // Each id reports its OWN line, not the line the array opened on. Vendor
  // attribution is measured in lines from the pin, so a whole array collapsed
  // onto one line would attribute every entry from the same neighbourhood.
  const lines = pins.map((p) => p.line);
  check("each id carries its own line number", new Set(lines).size, 2);

  for (const pin of pins) {
    check(`${pin.id} attributes to groq`, attribute(KIVVI_TYPED_ARRAY, pin.line), "groq");
  }

  const regions = modelListRegions(KIVVI_TYPED_ARRAY);
  check("exactly one models array is found in the file", regions.length, 1);
}

{
  // The plain shapes must keep working.
  check("a one-line string form still reads", extractPins(`const model = 'openai/gpt-oss-120b'`).map((p) => p.id), ["openai/gpt-oss-120b"]);
  check(
    "a plain inline array still reads",
    extractPins(`models: ['openai/gpt-oss-120b', 'openai/gpt-oss-20b']`).map((p) => p.id).sort(),
    ["openai/gpt-oss-120b", "openai/gpt-oss-20b"],
  );
  check(
    "an assignment without an annotation still reads",
    extractPins(`const models = [\n  "openai/gpt-oss-120b",\n]`).map((p) => p.id),
    ["openai/gpt-oss-120b"],
  );
}

console.log(failures ? `\n✗ ${failures} failure(s)` : "\n✓ all checks pass");
process.exit(failures ? 1 : 0);
