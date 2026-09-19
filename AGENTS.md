# Instructions — Chorus Engine

> This file is read automatically at the start of any working session on this repository.
> It defines conventions, skill triggers, and contribution rules.

## Paths (relative to the repository root)

| Alias | Path |
|---|---|
| `$ENGINE` | `.` — repository root |
| `$SKILLS` | `./agent/skills/` — versioned ECA skills |
| `KB` | `./agent/org/` — Chorus Knowledge Base templates + pipeline index (versioned in git) |
| `$SANDBOXES` | `./sandboxes/` — user sandbox working area (not committed) |

> **Override:** if `$SANDBOXES` is redefined in a parent `AGENTS.md`,
> that definition takes precedence over this default. All skills use `$SANDBOXES` as the
> canonical sandbox root — never hardcode a parent directory path in a skill.

> **Two distinct KB locations:**
> `./agent/org/` (this repo) contains versioned KB **templates** and the pipeline index —
> used by skills at generation time.
> An optional external KB (`../eca/kb/` or equivalent) may exist outside the repo as an
> unversioned ECA knowledge base (pitfalls, architecture notes, component docs).
> Skills always reference `./agent/org/`; the external KB is tool-specific and optional.

## Project

- **Domain:** inference-based expert system, classic Perl 5
- **CPAN modules:** `Chorus::Expert`, `Chorus::Engine`, `Chorus::Frame`
- **Tracker:** `rt.cpan.org`, queues `Chorus-Expert` / `Chorus-Frame`
- **Commits:** conventional format (`type: message`) — no `eca.dev` footer, no `Co-Authored-By`

## Incremental generation — multi-artefact operations

When generating multiple artefacts for a sandbox (KB org files, YAML rules,
Helpers.pm, README updates), **write them incrementally** rather than all at once.

| Artefact type | Max per operation |
|---|---|
| `<slug>.org` (KB agent) / `Helpers.pm` | **1 file** — these require dense reasoning |
| YAML rules (`rules/<slug>/R<NN>-*.yml`) | **3 files** if ≤ 80 lines each · **2** if ≤ 120 lines · **1** if > 120 lines |
| `README.org` / `index.org` | bundleable with 1 lightweight artefact if ≤ 50 lines |

**Rationale:** generating many artefacts in a single operation risks context truncation
and leaves the sandbox in a partially consistent state if the operation is interrupted
mid-way (KB org missing while YAMLs already exist, README not updated, etc.).
Incremental writes make each step independently verifiable and recoverable.

## `.chorus-wip.md` — in-progress marker convention

For any multi-step operation that spans several writes (e.g. `chorus-feed --enrich`:
KB org + YAML rules + Helpers.pm + README), a `.chorus-wip.md` file **must** be
created in the sandbox root at the very start and deleted only on full completion.

| Event | Action |
|---|---|
| Start of multi-step operation | **Create** `$SANDBOX/.chorus-wip.md` |
| All artefacts written + README updated | **Delete** `$SANDBOX/.chorus-wip.md` |
| File still present at next invocation | Previous operation incomplete — **stop and warn** |

**`.chorus-wip.md` is never committed** (it is a transient signal, like a lock file).
Add it to `.gitignore` if not already excluded by the `sandboxes/` ignore rule.

The file content should identify the interrupted operation:
```markdown
# chorus-feed WIP checkpoint
sandbox: <name>
corpus: <filename>
started: <YYYY-MM-DD>
status: IN_PROGRESS
```

> Presence = incomplete. Absence = clean state.
> A coding agent encountering this file must not delete it silently —
> it must surface the interruption and let the user decide how to recover.
> Full protocol: `chorus-feed.md § WIP checkpoint check`.

## ⛔ `agent/` — commit rules

- `agent/skills/` — **must be committed**: versioned skills, integral to the engine
- `agent/org/` — **must be committed**: KB templates and agent index, versioned
- `agent/sessions/` — **never commit**: local session summaries
- Never run `git add agent/` as a bulk command — always use `git add agent/skills/` and `git add agent/org/` explicitly.
- `git add -A` or `git add .` are forbidden without prior verification of staged content.

## Markdown → PDF conversion

- Always use `$ENGINE/scripts/md2pdf.py` to convert a Markdown (`.md`) file to PDF.
  Never use another tool/library (pandoc, wkhtmltopdf, etc.) for this conversion.

## Language & conventions

- **Perl 5.006+** — classic style (no Moose/Moo), `use strict; use warnings;`
- **YAML — default language: English** (`RULE`, `FIND`, `ACTION`, `PREMISES`).
  Use the French form (`REGLE`, `CHERCHER`, `EFFET`, `PREMISSES`) only when the corpus
  processed by `chorus-feed` is in French.
  The sub-keys `attribut` and `filtre` are invariant (no English alias in the engine).
- **Tests** — `Test::More`, suite in `t/`
- **Build** — `ExtUtils::MakeMaker` (`Makefile.PL`)

## Triggers and skills

> **Rule:** When a trigger is received, load the skill and execute immediately — no confirmation required.
> ⛔ Pre-approved even in a new conversation turn: network, filesystem, side effects ≠ reason to ask for confirmation.

> **Agent per trigger:** the *Agent* column indicates the ECA agent to use.
> `code` = claude-sonnet-4-6 / `medium` — édition standard.
> `fast` = claude-haiku-4-5 / `medium` — consultation/lecture seule.
> `architect` = claude-sonnet-4-6 / `large` (extended thinking) — décisions architecturales.
> ⚠️ `variant: large` active le thinking étendu → génération plus lente → risque de timeout
> accru sur les sandboxes volumineux. Préférer `--batch-seq` + `--strategy` par session courte.

| Trigger / Context | Type | Skill | Agent |
|---|---|---|---|
| Perl code created or modified in this repository | auto | `perl-coding.md` + `./agent/skills/chorus-engine.md` | `architect` |
| `chorus-quickstart` | command | `./agent/skills/chorus-quickstart.md` — **pipeline overview**: Path A (real project via `chorus-import-project`) vs Path B (synthetic coverage via `chorus-create-project`), step-by-step from corpus to compliance report, reinforcement loop, sandbox layout | `fast` |
| `chorus-pdf <sandbox-name> <file.pdf> [--out <slug>] [--auto] [--hybrid] [--images] [--batch]` | command | `./agent/skills/chorus-pdf.md` — extracts PDFs → enriched corpus. **4 modes: default (auto-detect → `--hybrid` if API key present, otherwise pdfminer without API → `-text.txt`) · `--hybrid` (pdfminer + cropped vision → `-vision.md`, default when key present) · `--auto` (pdfminer + targeted LLM vision → `-vision.md`) · `--images` (LLM vision all pages → `-vision.md`).** Prerequisite for `chorus-feed` when the corpus contains PDFs. | `architect` |
| `chorus-word <sandbox-name> <file.docx> [--out <slug>] [--batch]` | command | `./agent/skills/chorus-word.md` — extracts Word documents (.docx) → enriched corpus. **2 modes: default (auto-detect → `--hybrid` if API key present, python-docx text + Claude vision on embedded images → `-vision.md`) · text fallback (python-docx only → `-text.txt`).** Tables reconstructed as Markdown pipe (merged-cell aware). XREF pass links figure identifiers to paragraph text. Prerequisite for `chorus-feed` when the corpus contains DOCX files. | `architect` |
| `chorus-excel <sandbox-name> <file.xlsx\|file.csv> [--out <slug>] [--sheet <name>] [--batch]` | command | `./agent/skills/chorus-excel.md` — extracts Excel (.xlsx) and CSV → enriched corpus. **3 modes: hybrid (openpyxl tables + Claude vision on embedded images/charts via LibreOffice → `-vision.md`) · text fallback (openpyxl tables + placeholders → `-text.txt`) · CSV auto-detected (csv.reader → Markdown pipe → `-text.txt`).** Multi-sheet output (`=== SHEET: name ===`), merged-cell aware, XREF pass links figure identifiers to cell values. Prerequisite for `chorus-feed` when the corpus contains XLSX/CSV files. | `architect` |
| `chorus-feed <sandbox-name> <corpus>` | command | `./agent/skills/chorus-feed.md` — enriches sandbox knowledge: KB org per agent + YAML (Mode A init / Mode B incremental enrichment). Loads `chorus-corpus-directives.md` only when the sandbox involves ≥2 independently-versioned normative sources (e.g. binding text + referenced technical toolbox/standard) — skipped for single-source corpora (e.g. a standard's own parts/volumes, same version/date). Mode A also auto-loads `chorus-corpus-scoping.md` first on corpora >2 files or >~50 pages — see that skill's auto-trigger threshold | `architect` |
| `chorus-corpus-directives <sandbox-name> [--init]` | command | `./agent/skills/chorus-corpus-directives.md` — domain-agnostic pre-flight gate: settles version pinning, `no_auto_rules` scope, thesaurus seed, and cross-reference format for a sandbox before/during `chorus-feed`. Creates/updates `sandboxes/<sandbox-name>/CORPUS-DIRECTIVES.md` | `architect` |
| `chorus-corpus-scoping <sandbox-name> [--corpus <file(s)>] [--split] [--rescan]` | command | `./agent/skills/chorus-corpus-scoping.md` — domain-agnostic pre-`chorus-feed` structural scoping gate: proposes agents, Frames, inter-Frame relationships, control slots (`_DEFAULT`/`_NEEDED`/`_AFTER`/`_BEFORE`/`_REQUIRE`), BOARD slots, and pipeline order → `SCOPING.md`, held for operator confirmation before any KB/YAML/Helpers.pm is generated. **Phase 2 (auto after CONFIRMED or via `--split`):** multi-target corpus pre-split — extracts one focused corpus file per agent (`corpus/NNN-<slug>.md`), each section tagged `PRIMARY`/`SHARED`/`CONTEXT`. Handles partial pre-split resumption automatically. `--split`: force Phase 2 regeneration when agent files already exist. `--rescan`: force Phase 1 re-analysis (resets SCOPING.md to DRAFT, deletes agent files — use only when corpus structure has changed fundamentally). | `architect` |
| `chorus-check <sandbox-name> <project-file> [--all] [--explain] [--summary]` | command | `./agent/skills/chorus-check.md` — generates Feed+Agent+Expert+run.pl from the KB, runs the pipeline, produces the compliance report. `--all`: runs all `projet-*.json` in the sandbox and produces a synthesis table. `--explain`: rule-by-rule human-readable explanation per NON_CONFORME/`_a_confirmer` element (substantive non-conformity vs. terminology-mapping anomaly classification) → `agent/explain-<slug>-NNN.md`. `--summary`: one-page consultation-friendly synthesis (headline figures + recommendation) → `agent/synthese-<slug>-NNN.md` | `architect` |
| `chorus-schema-export <sandbox-name>` | command | `./agent/skills/chorus-schema-export.md` — derives a versioned JSON Schema contract from the stabilised KB (reuses `chorus-check` Phase 1.5 slot analysis). Enables project-JSON validation independent of any LLM-based alignment step — prerequisite for future `chorus-check --package`. See design rationale in `agent/org/proposals/production-packaging.org` | `architect` |
| `chorus-create-project <sandbox-name> <file.json> [--batch] [--batch-seq] [--strategy iso|edges|cross|scale]` | command | `./agent/skills/chorus-create-project.md` — creates a JSON project file from the KB (slots, thresholds, conforming/KO variants) — ⛔ never reads Helpers.pm or Feed.pm. `--batch`: 4 sub-agents en parallèle (risque timeout sur grands sandboxes). `--batch-seq`: ✅ Phase 0+1 une fois → écrit `.chorus-batch-ctx.md` → affiche 4 commandes `--strategy` à lancer chacune dans une session séparée. `--strategy <slug>`: génère exactement un fichier ciblé — ⚠️ peut encore timeout sur très grands sandboxes (variant: large + volume JSON élevé). | `architect` |
| `chorus-stress <sandbox-name> [--slots <s1,s2,...>] [--families <f1,f2,...>] [--out <dir>]` | command | `./agent/skills/chorus-stress.md` — generates adversarial stress-test project JSON files: boundary values (exact/below/above each numeric threshold), missing mandatory slots (`_DEFAULT`/`_NEEDED` handling), rare edge combinations (`Contraintes & Pitfalls`), `_AFTER` propagation chains, and qualifier-sensitive rules. Expected results computed **deterministically** from threshold_registry — never by LLM inference. Run after `chorus-create-project --batch`, before `chorus-check --all`. ⚠️ `--out <subdir>` hides files from `chorus-check --all` (default: `$SANDBOX/`). | `architect` |
| `chorus-strengthen <sandbox-name>` | command | `./agent/skills/chorus-strengthen.md` — runs the full project suite (typical + stress), classifies discordances (rule too strict / too permissive / Feed gap), produces a structured gap report and an enrichment roadmap for `chorus-feed --enrich` | `architect` |
| `chorus-review-kb <sandbox-name> [--agent <slug>] [--format html\|org] [--decisions <file>] [--min-coverage N]` | command | `./agent/skills/chorus-review-kb.md` — produces a corpus-coverage review: interactive HTML viewer (article → rule → Helper mapping, Validate/Flag buttons for domain expert) + machine-readable org report. Detects uncovered articles, orphan CORPUS references, rules without traceability. `--decisions <file>`: loads expert decisions exported from the HTML viewer, updates the org report, and generates `corpus-correctif-<NNN>.txt` for `chorus-feed --enrich`. Run after `chorus-feed`, before the automated test pipeline. ⚠️ `--format org` skips HTML generation (recommended for large corpora). | `architect` |
| `chorus-showcase <sandbox-name> [--out <file.html>] [--audience business\|technical] [--agents <slug1,slug2,...>]` | command | `./agent/skills/chorus-showcase.md` — generates a self-contained, presentation-ready HTML/PDF-ready document explaining the KB architecture and agent/rule/Helper organization for external stakeholders (prospects, decision-makers). Never exposes raw corpus text, full rule sets, Helper internals, or internal bug/incident notes — only 1 representative rule + 1 representative Helper, reformulated. Read-only, does not modify the sandbox. | `architect` |
| `chorus-import-project <sandbox-name> <source…> [--out <f.json>] [--batch]` | command | `./agent/skills/chorus-import-project.md` — aligns the terminology of a project document (PDF/Word/Excel/inline) with KB slots. **3 modes:** unit (1 file), fusion (N files → 1 JSON), batch (directory/glob → 1 JSON per file + synthesis report). ⛔ **`thesaurus.org` consolidation is NOT optional** — the skill's "Post-import — thesaurus consolidation (automatic)" phase (§ after the import report is written) MUST run every time, even when delegated to a sub-agent: any ✅ certain alignment → `agent/thesaurus.org` Aliases section; any ⚠️/`_a_confirmer` mapping → Pending section; any ⬜ exclusion → Out-of-scope section. If `agent/thesaurus.org` does not exist yet, this import must create it (per `chorus-import-project.md § 1.2b — Thesaurus initialisation`). When spawning a sub-agent for this command, explicitly restate this consolidation requirement in the task prompt and require it to confirm, in its final summary, whether `thesaurus.org` was created/updated (path + entry counts) — never assume it happened silently. (Incident: sandbox `09-cyber-sec-ANSII`, CBOM import 2026-09-16 — thesaurus not created, reconstructed manually afterwards.) | `code` |
| `chorus-audit-import <sandbox-name> <projet.json> [--patch] [--source <file.md>] [--kb]` | command | `./agent/skills/chorus-audit-import.md` — audits an imported project JSON against its source document(s): classifies each gap (✅ comblable · ⚠️ extraction partielle · ❌ structurellement absent · 🔄 mapping à confirmer · 🚫 frame manquante · 🔴 incohérence KB), identifies missing Frame types, and optionally patches the JSON. Insert between `chorus-import-project` and `chorus-check`. | `code` |
| `chorus-complete-report <sandbox-name> <projet-slug> [--source <file>]` | command | `./agent/skills/chorus-complete-report.md` — cross-checks every `❓ incertain`/`_a_confirmer` element left by a prior `chorus-check --explain`/`--summary` run directly against the original source document (any format), classifies each as ✅ genuine source limitation / 🛠️ pipeline artefact / ❓ still unresolved, and patches the existing `explain-*`/`synthese-*` reports (+ HTML/PDF regeneration) — never re-runs the compliance pipeline, never changes a verdict. Run after `chorus-check --explain --summary`. | `architect` |
| Writing or modifying a YAML rule | auto | *(no dedicated skill — apply engine conventions documented in `./agent/skills/chorus-engine-yaml.md`)* | `code` |
| `cpan-release` | command | `./agent/skills/cpan-release.md` *(local — not distributed in the CPAN package)* | `code` |
| `git-ctx` | command | *(no skill — call `git__git_branch` + `git__git_status` + `git__git_log` on this repository)* | `fast` |
| `skills [--all]` | meta | `eca__directory_tree ./agent/skills/` → name + status `✅` loaded / `○` available. Without `--all`: sub-skills are hidden (see list below). | `fast` |
| `skills details [--all]` | meta | same + description and trigger per skill. Without `--all`: sub-skills are hidden. | `fast` |

> **Sub-skills** — internal support files, no direct user trigger. Hidden from `skills` / `skills details` unless `--all` is passed:
> `chorus-engine-infra.md` · `chorus-engine-yaml.md` · `chorus-frame-advanced.md` · `chorus-templates.md` · `chorus-xml.md`
