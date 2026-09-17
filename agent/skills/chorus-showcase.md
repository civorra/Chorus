# Skill — chorus-showcase

> **Trigger:** `chorus-showcase <sandbox-name> [--out <file.html>] [--audience business|technical] [--agents <slug1,slug2,...>]`
> **Agent:** `architect`
>
> `<sandbox-name>` : sandbox with a KB produced by `chorus-feed` (README.org + agent/chorus/*.org
>   + rules/ + lib/ must exist)
> `--out <file.html>` : output path (default: `$SANDBOX/showcase-<NNN>.html`)
> `--audience business|technical` *(default: business)* :
>   - `business` — decision-maker facing: no YAML/Perl syntax shown, concepts translated to
>     plain language, emphasis on traceability/auditability/scalability as selling points.
>   - `technical` — same structure but keeps 1 real YAML snippet and 1 real Perl Helper
>     snippet verbatim (for a technical evaluator/architect audience).
> `--agents <slug1,slug2,...>` : restrict the "pipeline" and "representative rule" sections
>   to specific agents (default: auto-select — see Phase 3).
>
> **Single responsibility: produce a self-contained, presentation-ready HTML (or PDF-ready
> HTML) document that explains the *role and architecture of the KB* and the *organization
> and value of the agents/rules/Helpers* for a sandbox — without ever exposing the sandbox's
> raw corpus, full rule set, bug logs, or internal engineering notes.**
>
> This skill is a **communication artifact generator**, not a technical audit tool
> (see `chorus-review-kb.md` for that). It is meant for external stakeholders: prospects,
> clients, decision-makers evaluating Chorus adoption.
>
> It does NOT modify any KB, YAML, Helper, or README file. Read-only on the sandbox.

---

## ⛔ Hard exclusions — never include in the output

The showcase document must **never** contain:
- The raw corpus text (PDF extraction `.md`/`.txt` files) — only *section titles* as references
  (e.g. "§2.2.1.1 — Factorisation"), never verbatim normative paragraphs beyond a short quote
  (≤ 2 lines) used as illustration.
- The full YAML rule set or full Helper.pm files — only ONE representative rule and ONE
  representative Helper, reformulated in plain language (business mode) or shown as a short
  verbatim excerpt (technical mode, ≤ 30 lines).
- Any "Bugs corrigés" / internal engineering incident section from the README — these are
  internal QA notes, not demo material. If referenced at all, reformulate positively
  (e.g. "structural consistency checks validated before delivery") — never describe the bug itself.
- `SCOPING.md` / `CORPUS-DIRECTIVES.md` operator-facing arbitration notes verbatim.
- File paths, Perl package internals, or any content that would let a reader reconstruct
  the sandbox's proprietary rule set from the document alone.

If in doubt about a piece of content: prefer paraphrase over exposure.

---

## Phase 0 — Preconditions

1. Verify the sandbox exists and has been through `chorus-feed` (README.org with a
   "Pipeline" or "Identified pipeline" section, `agent/chorus/index.org`, at least one
   `rules/<agent>/*.yml`, at least one `lib/.../Agent/*.pm`).
2. If `agent/chorus/index.org` is missing, stop and report — this skill requires a
   completed Mode A (or Mode A+B) generation pass.

## Phase 1 — Read source material (read-only)

Read, in order:
1. `$SANDBOX/README.org` — corpus table, pipeline table, agent status table.
   ⚠️ Skip/ignore the "Bugs corrigés" and "Problèmes / ambiguïtés signalés" sections entirely
   when extracting content for the showcase.
2. `$SANDBOX/agent/chorus/index.org` — pipeline consistency, targeting slots, BOARD slots.
3. For each agent referenced in the pipeline table (or the subset given via `--agents`):
   `$SANDBOX/agent/chorus/<slug>.org` — read only the `* Domaine` and `* Ontologie` sections
   (skip `* Pipeline I/O` low-level slot tables and `* Constraints & Pitfalls` unless a specific
   pitfall makes a compelling "rigor" argument when reformulated positively).
4. Count rules per agent via `rules/<slug>/*.yml` file listing (do not read all of them).

## Phase 2 — Select representative artifacts

Do not showcase everything. Select:
- **1 representative KB agent** — prefer one with both a clear normative anchor (article
  reference) and, if available, at least one Helper.
- **1 representative rule** (YAML) — prefer a rule with a clean threshold logic and a
  `motif_*` justification string (good narrative material), from the agent selected above.
- **1 representative Helper** (Perl) — prefer one that performs *empirical enrichment*
  (e.g. a lookup table of real-world benchmark/record data) rather than a pure arithmetic
  helper — this is the strongest differentiator argument (see Phase 4 messaging).

If `--agents` is given, select the representative rule/Helper from within that scope only.

## Phase 3 — Auto-select pipeline scope

If the sandbox pipeline has more than ~6 agents, group them into logical clusters
(as documented in `index.org` "Pipeline consistency", e.g. independent Frame-based groups)
rather than listing all agents flat. Each cluster gets one line in the pipeline diagram
with an aggregate rule count, and its own synthesis/termination agent called out.

## Phase 4 — Generate the HTML document

Single self-contained HTML file (inline `<style>`, no external dependencies, printable to
PDF via browser print-to-PDF). Structure — 6 sections, target 4-6 printed pages:

1. **Positioning / cover** — sandbox domain in plain language, corpus sources (title +
   publisher + version, no raw text), headline numbers (N agents, N rules, N corpus documents,
   traceability claim).

2. **KB architecture** (3-layer diagram: Normative corpus → KB org (source of truth) →
   Executable engine (YAML rules + Perl Feed/Expert)). Key message: the KB is not
   after-the-fact documentation — it is what generates the rules and drives the Helpers;
   every rule carries an opposable article reference by construction. Include the
   Ontology/aliasing point (business vocabulary reconciled automatically with canonical
   engine vocabulary) as a concrete example (2-3 alias pairs from the `* Ontologie` section
   read in Phase 1, no more).

3. **Agent pipeline** (diagram from Phase 3 clusters). Key message: incremental extensibility
   — if the sandbox has an enrichment pass (Mode B / new corpus added), state that the
   pipeline was extended without rewriting existing agents (this is a scalability proof point;
   phrase generically, do not reproduce the enrichment log).

4. **Rules — what makes them robust** — present the ONE representative rule selected in
   Phase 2, reformulated in plain business language (business mode) or with a short verbatim
   excerpt (technical mode). Emphasize structural guardrails present in the engine's rule
   grammar: eligibility condition, non-recomputation guard, explainable justification string
   — phrase as generic engine capabilities, not as sandbox-specific YAML syntax.

5. **Helpers — proof by empirical evidence** — present the ONE representative Helper.
   Core selling message (adapt wording, keep the substance): *"The engine doesn't just say
   NON-COMPLIANT — it cites the most recent real-world benchmark that justifies the
   threshold, the way a human expert would."* This is the strongest differentiator vs.
   classic static rule engines (Drools-style fixed thresholds with no living justification).

6. **Reliability by construction** — one paragraph, positively framed, no incident detail:
   structural consistency of the pipeline (synthesis agents correctly targeted, output slots
   consolidated) is verified before any compliance report is delivered to a client.

## Phase 5 — Output

- Write the HTML file to `--out` path (default `$SANDBOX/showcase-<NNN>.html`, `<NNN>` =
  next available 3-digit sequence in the sandbox root).
- Confirm to the user with the file path and a one-line reminder: "Browser → Print → Save as PDF"
  for a PDF deliverable.
- Do NOT commit this file automatically — showcase artifacts are sandbox-local deliverables,
  same governance as other generated sandbox content (operator decides if/when to share).

## Notes on tone

- Written for a decision-maker or technical evaluator meeting, not for an auditor.
- Confident, concrete, numbers-driven — avoid hedging language ("aims to", "attempts to").
- Every claim should be traceable to something actually present in the sandbox (no invented
  metrics) — if a number isn't in the README/index.org, don't state it.
