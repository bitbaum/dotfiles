#!/usr/bin/env node
/**
 * Fleet audit: is any model id this fleet pins no longer served?
 *
 * WHY THIS EXISTS
 * ---------------
 * On 2026-08-26 the AOZ assistant answered "KI-Assistent nicht konfiguriert.
 * Bitte GROQ_API_KEY setzen" on a deployment whose key was valid. Groq had
 * retired the whole llama-3.x family; the pinned `llama-3.3-70b-versatile`
 * returned 404 model_not_found. Production had been broken as long as the demo
 * and nobody knew, because the only thing the app can say is "not configured".
 *
 * That is not an AOZ bug. Every Groq id pinned anywhere in the fleet was dead
 * the same morning — llama-3.1-8b-instant, llama3-8b-8192, gemma2-9b-it,
 * mixtral-8x7b-32768, llama-3.2-3b-instruct — across eleven repos, with three
 * deployed apps failing live.
 *
 * A pinned free model is not a configuration, it is a scheduled outage. The
 * schedule is set by the vendor and nobody here is told. So this asks the only
 * authority that knows: the vendor's own catalogue.
 *
 * WHY A CENTRAL SCRIPT AND NOT A CHECK PER REPO
 * ---------------------------------------------
 * Same doctrine as verify-floor-audit.sh and ui-defect-audit.mjs. A check
 * copied into twenty repos drifts into twenty versions — SHARED.md counts the
 * bill for exactly that habit. More to the point, a per-repo check only ever
 * runs in repos somebody still touches, and the repos that rot quietly are
 * precisely the ones nobody touches. This one needs no adoption at all.
 *
 * WHY IT REUSES ai-ration
 * -----------------------
 * `checkCatalog` already answers this, already distinguishes the three states
 * that matter, and already carries the scars — its own docstring records four
 * of nine default pins gone and a consumer silently failing for eight days.
 * Writing a second vendor query here would be this repo committing the sin it
 * exists to police. It takes the chain as an ARGUMENT, so it generalises to
 * arbitrary ids with no change to the package.
 *
 * ZERO TOKENS, WHICH IS THE WHOLE POINT
 * -------------------------------------
 * One GET /models per vendor. No completion, no spend. That is the difference
 * between a check that runs on a timer and a command somebody is supposed to
 * remember — and "supposed to remember" is what failed for eight days.
 *
 * WHAT IT DOES NOT PROVE
 * ----------------------
 * That a listed model WORKS. Existence is cheap; capability is not. A model
 * can be listed and still refuse tool calls — of nine free models probed for
 * ai-ration's default chain, five answered only via a text protocol. If the
 * surface is a tool loop, probe with a real tool call before pinning. This
 * audit catches the retirement, not the mismatch.
 *
 * It also judges only ids it can ATTRIBUTE to a vendor it queried. An
 * unattributed id is reported and not judged, because "I could not look" and
 * "it is gone" are different answers and collapsing them invents outages.
 *
 * Usage:
 *   node scripts/ci/model-pin-audit.mjs                # audit, exit 1 on dead pins
 *   node scripts/ci/model-pin-audit.mjs --warn-only    # report, always exit 0
 *   node scripts/ci/model-pin-audit.mjs --local        # scan ~/dev checkouts
 *
 * Env: GH_OWNER (default maonakamoto), GH_LIMIT (default 100),
 *      FLEET_ROOT (default ~/dev, --local only),
 *      AI_RATION_FROM (path to a repo that installs ai-ration),
 *      GROQ_API_KEY / OPENROUTER_API_KEY (to read the catalogues).
 */
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import { join } from "node:path";
import { homedir } from "node:os";

const exec = promisify(execFile);

const WARN_ONLY = process.argv.includes("--warn-only");
const LOCAL = process.argv.includes("--local");
const OWNER = process.env.GH_OWNER ?? "maonakamoto";
const GH_LIMIT = process.env.GH_LIMIT ?? "100";
const FLEET_ROOT = process.env.FLEET_ROOT ?? join(homedir(), "dev");

/**
 * The vendors whose catalogue we can actually read, and the markers that tie a
 * pin to one of them.
 *
 * Attribution is by MARKER rather than by the shape of the id, because the shape
 * lies: `openai/gpt-oss-20b` is a Groq model id AND an OpenRouter routing id,
 * and at OpenRouter the missing `:free` suffix is the difference between free
 * and billed. Only the surrounding code knows which vendor is meant.
 */
export const VENDORS = [
  {
    id: "groq",
    queryable: true,
    baseUrl: "https://api.groq.com/openai/v1",
    keyEnv: "GROQ_API_KEY",
    markers: [/groq/i],
  },
  {
    id: "openrouter",
    queryable: true,
    baseUrl: "https://openrouter.ai/api/v1",
    keyEnv: "OPENROUTER_API_KEY",
    markers: [/openrouter/i],
  },
  // Not queryable here — no catalogue call is wired for these. They are listed
  // so their ids are ATTRIBUTED and reported unchecked, rather than falling to
  // whichever queryable vendor happens to sit nearest in the file. Markers are
  // deliberately specific: bare /openai/ would match Groq's own
  // `api.groq.com/openai/v1` path and every `openai/gpt-oss-*` id it serves.
  { id: "xai", queryable: false, markers: [/api\.x\.ai/i, /\bXAI_API_KEY\b/, /\bgrok\b/i] },
  { id: "anthropic", queryable: false, markers: [/api\.anthropic\.com/i, /\bANTHROPIC_API_KEY\b/] },
  { id: "openai", queryable: false, markers: [/api\.openai\.com/i, /\bOPENAI_API_KEY\b/] },
  { id: "google", queryable: false, markers: [/generativelanguage\.googleapis/i, /\bGEMINI_API_KEY\b/] },
];

/**
 * Files worth opening, in two tiers.
 *
 * LIKELY names an AI module outright. POSSIBLE is the long tail that a
 * name-based filter misses: botsmann keeps its model id in `lib/constants.ts`,
 * which mentions no vendor in its path and was invisible to the first version
 * of this filter. A pin does not have to live in a file called `provider.ts`.
 */
const LIKELY_PATH =
  /(^|\/)\.env\.example$|(^|\/)env\.(ts|js|mjs)$|(^|\/)(lib|src|app|apps|packages|config)\/.*(provider|model|llm|chat|ai|openai|anthropic)[^/]*\.(ts|js|mjs)$/i;

const POSSIBLE_PATH =
  /(^|\/)(lib|src|app|apps|packages|config)\/.*(constants?|config|settings|defaults)[^/]*\.(ts|js|mjs)$/i;

const CANDIDATE_PATH = new RegExp(`(${LIKELY_PATH.source})|(${POSSIBLE_PATH.source})`, "i");

/** Never open these, whatever they are named. */
const SKIP_PATH =
  /(^|\/)(node_modules|dist|build|\.next|coverage|__tests__|__fixtures__)\/|(^|\/)\.claude\/worktrees\//;

const MAX_FILES_PER_REPO = 90;

/** A vendor named 40+ lines from a pin is not describing that pin. */
const MAX_ATTRIBUTION_DISTANCE = 40;

// ── Extraction ───────────────────────────────────────────────────────────────

/**
 * Is this string plausibly a model id rather than any other quoted thing?
 *
 * Deliberately permissive on shape and strict on the obvious negatives. A false
 * POSITIVE costs one line in a report that says "not judged"; a false NEGATIVE
 * is the outage this whole file exists to prevent.
 */
export function looksLikeModelId(s) {
  if (typeof s !== "string") return false;
  if (s.length < 3 || s.length > 80) return false;
  if (/\s/.test(s)) return false;
  if (s.includes("${")) return false; // interpolated: resolved at runtime, not pinned
  if (/^https?:/i.test(s)) return false;
  if (/^[./~@]/.test(s)) return false;
  if (/\.(ts|tsx|js|mjs|cjs|json|css|scss|md|png|jpe?g|svg|ico|txt|ya?ml)$/i.test(s)) return false;
  if (/^[A-Z][A-Z0-9_]*$/.test(s)) return false; // SCREAMING_CASE is an env name
  // Model ids essentially always carry a version digit or a vendor/ prefix.
  return /\d/.test(s) || s.includes("/");
}

/**
 * Pull candidate model ids out of one file's text, with the line each sits on.
 *
 * Three shapes cover how this fleet writes them:
 *   1. a `model:` / `models:` assignment, single value or array
 *   2. a *_MODEL constant or Zod `.default(...)`
 *   3. a bare `GROQ_MODEL=...` line in a .env file
 */
export function extractPins(text) {
  const found = new Map(); // id -> line number (first sighting)
  const lineOf = (index) => text.slice(0, index).split("\n").length;

  const remember = (id, index) => {
    if (!looksLikeModelId(id)) return;
    if (!found.has(id)) found.set(id, lineOf(index));
  };

  // 1. model: 'x'   |   models: ['a', 'b']
  for (const m of text.matchAll(/\bmodels?\s*[:=]\s*(\[[\s\S]{0,400}?\]|['"`][^'"`\n]{0,120}['"`])/gi)) {
    for (const q of m[1].matchAll(/['"`]([^'"`\n]+)['"`]/g)) remember(q[1], m.index);
  }

  // 2. GROQ_MODEL: z.string().default('x')   |   const DEFAULT_MODEL = 'x'
  for (const m of text.matchAll(
    /\b([A-Za-z][A-Za-z0-9_]*MODEL[A-Za-z0-9_]*)\s*[:=][^\n]{0,80}?['"`]([^'"`\n]+)['"`]/g,
  )) {
    remember(m[2], m.index);
  }

  // 3. .env style, unquoted or quoted, no code around it
  for (const m of text.matchAll(/^[ \t]*(?:export[ \t]+)?[A-Z][A-Z0-9_]*MODEL[A-Z0-9_]*\s*=\s*["']?([^"'\s#]+)/gm)) {
    remember(m[1], m.index);
  }

  return [...found].map(([id, line]) => ({ id, line }));
}

/**
 * Which vendor does this pin belong to?
 *
 * Nearest-marker first: a file can legitimately name both vendors — AOZ's
 * provider.ts resolves Groq AND OpenRouter in one module — so a file-wide vote
 * would attribute both vendors' pins to whichever appeared more. The pin's own
 * neighbourhood is what actually says which branch it is in. Only when the
 * window is silent do we fall back to the file, and only when the file names
 * exactly one vendor.
 *
 * Returns a vendor id, or null for "cannot tell" — which is reported, not judged.
 */
export function attribute(text, line, vendors = VENDORS, maxDistance = MAX_ATTRIBUTION_DISTANCE) {
  const lines = text.split("\n");

  /**
   * Distance to this vendor's nearest mention ABOVE the pin, and below it.
   *
   * Above is what decides. Every provider module in this fleet is written as
   * `if (provider === "groq") { url = ...; body = { model: "..." } }` — the
   * branch that owns a model literal always opens above it. Ranking by raw
   * proximity instead put `grok-3-mini` (xAI, line 89) with Groq, whose URL sat
   * at line 71, and tied kivvi's real Groq pin exactly between two vendors.
   */
  const distances = (vendor) => {
    let above = Infinity;
    let below = Infinity;
    for (let i = 0; i < lines.length; i++) {
      if (!vendor.markers.some((re) => re.test(lines[i]))) continue;
      const d = i + 1 - line;
      if (d <= 0) above = Math.min(above, -d);
      else below = Math.min(below, d);
    }
    return { above, below };
  };

  const scored = vendors.map((v) => ({ id: v.id, ...distances(v) }));

  const fromAbove = scored.filter((s) => s.above <= maxDistance).sort((a, b) => a.above - b.above);
  if (fromAbove.length === 1) return fromAbove[0].id;
  if (fromAbove.length > 1 && fromAbove[0].above < fromAbove[1].above) return fromAbove[0].id;

  // Nothing above governs it — a pin at the top of a file, or a config block
  // whose vendor is named afterwards. Fall back to the nearest mention below.
  if (fromAbove.length === 0) {
    const fromBelow = scored.filter((s) => s.below <= maxDistance).sort((a, b) => a.below - b.below);
    if (fromBelow.length === 1) return fromBelow[0].id;
    if (fromBelow.length > 1 && fromBelow[0].below < fromBelow[1].below) return fromBelow[0].id;
  }

  const named = vendors.filter((v) => v.markers.some((re) => re.test(text)));
  return named.length === 1 ? named[0].id : null;
}

/**
 * Turn per-file findings into per-vendor id lists plus the unattributable rest.
 * Pure, so the self-test can drive it without a network or a checkout.
 */
export function collate(findings) {
  const byVendor = new Map();
  const unattributed = [];

  for (const f of findings) {
    if (!f.vendor) {
      unattributed.push(f);
      continue;
    }
    if (!byVendor.has(f.vendor)) byVendor.set(f.vendor, []);
    byVendor.get(f.vendor).push(f);
  }
  return { byVendor, unattributed };
}

/**
 * Apply catalogue verdicts to the findings.
 *
 * `live` is a Map of vendorId -> Set of ids, or null for a vendor whose
 * catalogue could not be read. Null is NOT an empty set: treating "I could not
 * look" as "nothing is there" reports every pin as retired and invents an
 * outage, which is worse than silence because someone acts on it.
 */
export function judge(findings, live) {
  return findings.map((f) => {
    if (!f.vendor) return { ...f, state: "unattributed" };
    const set = live.get(f.vendor);
    if (!set) return { ...f, state: "unchecked" };
    return { ...f, state: set.has(f.id) ? "ok" : "gone" };
  });
}

// ── Reading the fleet ────────────────────────────────────────────────────────

/**
 * Which files get opened when a repo has more candidates than the cap allows.
 *
 * Ranked, never arbitrary: a file that names a vendor or an AI concern outranks
 * a generic `config.ts`, so the cap sheds the least likely candidates first.
 * And every truncation is RECORDED — a bounded sweep that stays quiet about
 * what it skipped reads exactly like a sweep that found nothing.
 */
const truncated = [];

function rank(paths, repoName) {
  const sorted = [...paths].sort((a, b) => {
    const ta = LIKELY_PATH.test(a) ? 0 : 1;
    const tb = LIKELY_PATH.test(b) ? 0 : 1;
    return ta - tb || a.length - b.length;
  });
  if (sorted.length > MAX_FILES_PER_REPO) {
    // What was dropped matters more than how many. Everything in the LIKELY
    // tier is opened first, so a truncation that sheds only generic config
    // files has not touched the audit's real coverage — and saying which it was
    // is the difference between a caveat and an alarm.
    const likelyDropped = sorted.slice(MAX_FILES_PER_REPO).filter((p) => LIKELY_PATH.test(p)).length;
    truncated.push({ repo: repoName, seen: sorted.length, opened: MAX_FILES_PER_REPO, likelyDropped });
  }
  return sorted.slice(0, MAX_FILES_PER_REPO);
}

async function gh(args) {
  const { stdout } = await exec("gh", args, { maxBuffer: 64 * 1024 * 1024 });
  return stdout;
}

/** Remote, default-branch view. Clones drift; this repo has been bitten by that. */
async function remoteRepos() {
  const raw = await gh([
    "repo", "list", OWNER,
    "--limit", String(GH_LIMIT),
    "--no-archived",
    "--json", "name,defaultBranchRef,isFork",
  ]);
  return JSON.parse(raw)
    .filter((r) => !r.isFork && r.defaultBranchRef?.name)
    .map((r) => ({ name: r.name, branch: r.defaultBranchRef.name }));
}

async function remoteFiles(repo) {
  let tree;
  try {
    tree = JSON.parse(
      await gh(["api", `repos/${OWNER}/${repo.name}/git/trees/${repo.branch}?recursive=1`]),
    );
  } catch {
    return []; // empty repo, or no access — not a finding
  }
  const all = (tree.tree ?? [])
    .filter((n) => n.type === "blob" && !SKIP_PATH.test("/" + n.path) && CANDIDATE_PATH.test(n.path))
    .map((n) => n.path);
  const paths = rank(all, repo.name);

  const out = [];
  for (const path of paths) {
    try {
      const body = JSON.parse(
        await gh(["api", `repos/${OWNER}/${repo.name}/contents/${path}?ref=${repo.branch}`]),
      );
      if (body.encoding !== "base64" || !body.content) continue;
      out.push({ path, text: Buffer.from(body.content, "base64").toString("utf8") });
    } catch {
      /* a path that vanished between tree and read is not a finding */
    }
  }
  return out;
}

function localRepos() {
  return readdirSync(FLEET_ROOT)
    .filter((n) => !n.startsWith("_") && existsSync(join(FLEET_ROOT, n, ".git")))
    .map((name) => ({ name, branch: "(local)" }));
}

function walk(dir, depth, acc) {
  if (depth < 0 || acc.length >= MAX_FILES_PER_REPO * 6) return acc;
  let entries;
  try {
    entries = readdirSync(dir, { withFileTypes: true });
  } catch {
    return acc;
  }
  for (const e of entries) {
    const full = join(dir, e.name);
    if (e.isDirectory()) {
      if (/^(node_modules|dist|build|\.next|coverage|\.git|\.claude)$/.test(e.name)) continue;
      walk(full, depth - 1, acc);
    } else if (CANDIDATE_PATH.test(full) && !SKIP_PATH.test(full)) {
      try {
        if (statSync(full).size < 400_000) acc.push(full);
      } catch { /* raced */ }
    }
  }
  return acc;
}

function localFiles(repo) {
  const root = join(FLEET_ROOT, repo.name);
  const all = walk(root, 6, []).map((full) => full.slice(root.length + 1));
  return rank(all, repo.name).map((path) => ({
    path,
    text: readFileSync(join(root, path), "utf8"),
  }));
}

// ── The catalogue, via ai-ration ─────────────────────────────────────────────

function loadAiRation() {
  const candidates = [
    process.env.AI_RATION_FROM,
    join(homedir(), "dev", "fleetcrown"),
    join(homedir(), "dev", "ai-ration"),
  ].filter(Boolean);

  for (const root of candidates) {
    for (const entry of [
      join(root, "node_modules", "ai-ration", "dist", "index.js"),
      join(root, "dist", "index.js"),
    ]) {
      if (existsSync(entry)) return import(entry);
    }
  }
  console.error(
    "✗ ai-ration not found. Set AI_RATION_FROM=/path/to/a/repo that installs it,\n" +
      "  or build it once: (cd ~/dev/ai-ration && npm i && npm run build)",
  );
  process.exit(2);
}

/**
 * Ask each vendor what it still lists, for exactly the ids we found.
 * Returns Map(vendorId -> Set|null), where null means "could not look".
 */
async function readCatalogues(byVendor, checkCatalog) {
  const live = new Map();
  for (const vendor of VENDORS) {
    if (!vendor.queryable) continue;
    const findings = byVendor.get(vendor.id);
    if (!findings?.length) continue;

    const ids = [...new Set(findings.map((f) => f.id))];
    const [verdict] = await checkCatalog([
      {
        id: vendor.id,
        baseUrl: vendor.baseUrl,
        keyEnv: vendor.keyEnv,
        models: ids,
        dailyTokens: 0,
      },
    ]);
    live.set(vendor.id, verdict.live ? new Set(verdict.live) : null);
  }
  return live;
}

// ── Report ───────────────────────────────────────────────────────────────────

function report(judged) {
  const gone = judged.filter((j) => j.state === "gone");
  const unchecked = judged.filter((j) => j.state === "unchecked");
  const unattributed = judged.filter((j) => j.state === "unattributed");
  const ok = judged.filter((j) => j.state === "ok");

  const lines = [];

  if (gone.length) {
    lines.push("RETIRED — the vendor no longer lists these, so every call using them fails:");
    const byId = new Map();
    for (const g of gone) {
      const key = `${g.vendor}/${g.id}`;
      if (!byId.has(key)) byId.set(key, []);
      byId.get(key).push(`${g.repo}:${g.path}:${g.line}`);
    }
    for (const [key, sites] of [...byId].sort()) {
      lines.push(`  GONE  ${key}`);
      for (const s of sites.sort()) lines.push(`          ${s}`);
    }
    lines.push("");
  }

  if (unchecked.length) {
    const vendors = [...new Set(unchecked.map((u) => u.vendor))].sort();
    lines.push(
      `${unchecked.length} pin(s) UNCHECKED — no readable catalogue for: ${vendors.join(", ")}.`,
    );
    lines.push("  That is not a pass for them. Set the vendor key to judge these.");
    lines.push("");
  }

  if (unattributed.length) {
    const ids = [...new Set(unattributed.map((u) => u.id))].sort();
    lines.push(`${unattributed.length} pin(s) not attributable to a vendor we query — listed, not judged:`);
    for (const id of ids.slice(0, 20)) lines.push(`  ?     ${id}`);
    if (ids.length > 20) lines.push(`  ?     … and ${ids.length - 20} more`);
    lines.push("");
  }

  lines.push(
    `${ok.length} pin(s) confirmed live · ${gone.length} retired · ` +
      `${unchecked.length} unchecked · ${unattributed.length} unattributed`,
  );

  if (truncated.length) {
    lines.push("");
    const blind = truncated.filter((t) => t.likelyDropped > 0);
    lines.push(`COVERAGE — ${truncated.length} repo(s) had more candidate files than the cap of ${MAX_FILES_PER_REPO}:`);
    for (const t of truncated) {
      const tail = t.likelyDropped > 0 ? `, ${t.likelyDropped} of them likely-AI` : ", none likely-AI";
      lines.push(`  ${t.repo}: opened ${t.opened} of ${t.seen}${tail}`);
    }
    lines.push(
      blind.length
        ? "  Files naming an AI concern were dropped — raise MAX_FILES_PER_REPO."
        : "  Only generic config files were dropped; every likely-AI file was opened.",
    );
  }

  if (gone.length) {
    lines.push("");
    lines.push("A pin is a scheduled outage. The durable fix is a chain across VENDORS —");
    lines.push("see SHARED.md → ai-ration. Repinning buys time until the next retirement.");
  }

  return lines.join("\n");
}

// ── Main ─────────────────────────────────────────────────────────────────────

export async function main() {
  const { checkCatalog } = await loadAiRation();

  const repos = LOCAL ? localRepos() : await remoteRepos();
  const findings = [];

  for (const repo of repos) {
    const files = LOCAL ? localFiles(repo) : await remoteFiles(repo);
    for (const file of files) {
      for (const pin of extractPins(file.text)) {
        findings.push({
          repo: repo.name,
          path: file.path,
          line: pin.line,
          id: pin.id,
          vendor: attribute(file.text, pin.line),
        });
      }
    }
  }

  const { byVendor } = collate(findings);
  const live = await readCatalogues(byVendor, checkCatalog);
  const judged = judge(findings, live);

  console.log(report(judged));
  console.log(`\ninspected ${repos.length} repo(s)${LOCAL ? " (local checkouts)" : " on their default branches"}`);

  const dead = judged.some((j) => j.state === "gone");
  process.exit(dead && !WARN_ONLY ? 1 : 0);
}

const invokedDirectly =
  process.argv[1] && import.meta.url === `file://${process.argv[1]}`;
if (invokedDirectly) {
  main().catch((err) => {
    console.error(`✗ audit failed: ${err?.message ?? err}`);
    process.exit(2);
  });
}
