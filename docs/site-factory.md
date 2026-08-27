# The Site Factory

Paste a link to a bad website. Get back a better one, plus a claimable
OrangeCat entity that can raise. Sell the improvement.

This file is the SSOT for where that pipeline lives. It exists because the
question "is this FleetCrown or OrangeCat?" has a real answer, and answering it
once is cheaper than answering it in every PR.

---

## Four things already exist. Build none of them twice.

| Asset | What it already solves |
|---|---|
| `substrata/config/site-content.ts` | **A site as data.** A closed union of section kinds (`hero`, `prose`, `stats`, `cards`, `definitions`, `index`, `table`, `meter`), pages as config, one catch-all route. |
| `camille-boulangerie` | The first sale-shaped artifact. Ships `DemoBanner.tsx`, and `HANDOVER.md` is a *rehearsed* handover with four findings. |
| `orangecat.profile_claims` | **A draft that is not a live profile until the subject claims it.** Row id is the claim token; no RLS policy, service-role only. |
| `orangecat.integration_keys` + `webhook_endpoints` | The outbound API path FleetCrown already uses. |

The generator does not need to be invented. It needs to be pointed at a schema
that already exists.

---

## The seam

Three layers, split where the boundary already falls.

### 1. `sitekit` — a shared package (new)

The section-shape schema, the renderers, and the extractor. Lift from Substrata,
which is the second instance of the pattern; Camille is the first and is
hand-rolled. Per `SHARED.md`, the third instance is where extraction stops being
premature — and "as many random sites as possible" *is* the third instance.

Why this is the whole efficiency argument: **the generator emits data, never
code.** An LLM filling a closed union of eight section kinds is a task with a
verifiable schema. An LLM writing `.tsx` is a task with no ground truth. Quality
per site becomes a property of the renderers — fix the `cards` renderer once and
every site ever generated gets better. That is the SSOT payoff at fleet scale.

Scope: schema + renderers + `siteFromUrl()` extraction. Ships **no** design
tokens — each site keeps its own `globals.css`, per the fleet's standing rule
that the system is uniform and the aesthetics are not.

### 2. FleetCrown — the pipeline

A prospect is a row with a state machine:

```
found → assessed → generated → reviewed → pitched → claimed → handed over
                                              ↓
                                          declined
```

FleetCrown already owns exactly this shape of thing: projects, crew assignments,
agent runs, prompt library, activity timeline. A prospect is a project that has
not said yes yet. It owns scraping, the assessment (what is actually wrong with
the current site — load time, mobile, contact info, last updated), the
generation run, the outreach record, and the handover checklist.

It does **not** own the entity. It calls OrangeCat.

### 3. OrangeCat — the claimable entity

Two pieces of work, and the second is the one worth doing first.

**a. Generalise `profile_claims` → entity claims.** Today the draft mirrors a
subset of `public.profiles` and nothing else — a person. A business needs a
group and a project that can raise. Same primitive, same token-is-the-id design,
same service-role-only posture; the `draft` jsonb grows a discriminated kind.

**b. Ingest: a link or free text → a draft.** This is the thing that was asked
for and does not exist. `POST /api/claims/ingest { url }` or `{ text }` → Cat
extracts → a pending claim. It is the same endpoint whether the caller is
FleetCrown's pipeline or a human typing a sentence to Cat, and that is the point:
the pipeline gets no privileged path a person cannot also use.

---

## Why this split and not "put it all in FleetCrown"

- **Blast radius.** Fundraising rules, claim tokens and identity live on one
  side of a network boundary. The prospecting pipeline cannot widen them by
  accident because it cannot reach the tables.
- **SSOT.** There is one definition of "an entity that can raise", and it is
  OrangeCat's. A second one inside FleetCrown would be a second source of truth
  about money.
- **The 2-files test.** Adding a section kind touches `sitekit` only. Adding a
  prospect state touches FleetCrown only. Adding a claimable entity kind touches
  OrangeCat only.

---

## The constraint that is not optional

Camille's own `HANDOVER.md` §4 already found this, against a real repository:

> This site was generated from a scrape of `juliette-boulangerie.ch` and
> pseudonymised. That is fine for a demo, and it is *not* transferable: you
> would be handing someone a restyled copy of a competitor's copy.

So pseudonymisation is not the safe path — it is the thing that makes the
artifact undeliverable. The names must split by purpose:

**Portfolio pieces** (Camille) — invented business, invented everything, clearly
fictional. You need a handful, not a hundred. These are safe to publish because
nobody is being represented.

**A pitch to a real business** — use their **real** name. That is what makes the
pitch land, it is ordinary spec work, and a near-miss name ("Bakery Juliett")
reads as either a mistake or a knock-off. What must be true instead:

- the page carries the `DemoBanner` — an unsolicited mockup, by the studio, not
  by them;
- it is not published under their identity: our subdomain, no claim to be their
  official site, `noindex` until they say yes;
- **fundraising is inert until claimed.** The architecture gives this for free
  *provided ingest writes to the claims table and never to `profiles`.* This is
  the single line in the design that must not be crossed: money must never be
  routable to an entity whose subject has not accepted it.
- takedown on request, immediately, no negotiation.

**Never fabricate the facts.** Not the address, not the hours, not the prices,
not reviews. A plausible-but-wrong street number is the one detail that actively
damages the business — customers arrive at the wrong door — and it makes the
artifact worthless as a deliverable, since every fabricated field has to be
found and rewritten before handover. Use what is public, and leave the rest
empty. Empty fields are also the pitch: *"this is what we could not find about
you in five minutes, which is what your customers also cannot find."*

And from the same rehearsal, two more that are part of the deliverable rather
than hygiene: the site must be in version control and in
`fleetcrown/scripts/hetzner/apps.conf` from minute one, and dependencies must be
current — Camille shipped on Next 14.2.35 with two high-severity advisories
against a fleet standard of 16.2.4.

---

## First slice

Smallest thing that is end-to-end real, in order:

1. **`sitekit` extracted from Substrata**, and Camille rebuilt on it. That
   rebuild is the test: if Camille cannot be expressed as data in the closed
   union, the union is wrong, and better to learn it on the site we already own.
2. **OrangeCat ingest endpoint** writing a pending claim from a URL. Person
   drafts only at first — the existing shape, new door.
3. **One real prospect, driven by hand** through the whole chain with no
   pipeline at all. The state machine should be written down only after a human
   has walked it once.
4. **Then** FleetCrown gets the prospect table, and only for the states step 3
   proved exist.

Steps 1 and 2 are independent and can run in parallel. Step 4 is the one to
resist starting early: a pipeline built before a single sale encodes guesses
about states that a real conversation will contradict.
