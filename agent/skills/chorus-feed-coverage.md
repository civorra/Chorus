# Sub-skill — chorus-feed-coverage

> **Internal sub-skill** — loaded by `chorus-feed.md` from both **Mode A** (Phase 6.5 —
> full coverage scan after initialization) and **Mode B** (Phase B4.5 — coverage delta
> after `--enrich`). Contains the logic genuinely identical between the two: the
> too-ambiguous retry protocol, the `README.org § Coverage` grammar contract, and the
> stability-point convergence check.
>
> **Not loaded standalone** — always entered from `chorus-feed.md § Phase 6.5` or
> `§ Phase B4.5`, which retain their own mode-specific steps (full corpus re-scan /
> mechanical inventory audit for Mode A; delta-against-existing-report logic / WIP
> checkpoint cleanup for Mode B) and call into this sub-skill only for the shared core
> below.
>
> Trigger: loaded via `eca__skill("chorus-feed-coverage")` from:
> - `chorus-feed.md § Phase 6.5 Step 2` (Mode A, first full classification)
> - `chorus-feed.md § Phase B4.5 Step 2` (Mode B, re-classification of the
>   `⏭ Deferred` / `🧮 Helper-source pending` backlog plus any newly discovered section)

## Classification protocol (Step 2a/2b/2c)

**Step 2a — First-pass classification into three buckets**

| Symbol | Bucket | Criterion |
|--------|--------|-----------|
| ✅ | **Integrated** | At least one YAML rule or Helper directly encodes this section |
| ⏭ | **Deferred — needs `--enrich`** | Section is normative and codifiable but not yet in the KB; state the reason |
| ⛔ | **Out of scope** | Section is informative, procedural without numeric threshold, or refers to external standards not in scope |

Deferred reasons (use one per entry):
- `multi-element` — rule involves a relationship between two distinct Frame types
- `diagram-dependent` — threshold is embedded in a complex figure (not a readable table)
- `external-norm` — rule defers to an external standard (BS EN, NF EN…)
- `procedural` — rule describes a process without a numeric threshold
- `too-ambiguous` — section wording is insufficiently precise to codify reliably
  *(only valid after Step 2b retry has failed — see below)*

**Sub-type tags ⏭-S / ⏭-C** (append to the reason, inline — e.g. `too-ambiguous / ⏭-S`):

| Tag | Meaning | Apply to motifs |
|---|---|---|
| `⏭-S` Structural | Section is too ambiguous or inaccessible — the corpus itself cannot produce a rule in its current state; no further `--enrich` pass will unblock it without a corpus revision | `too-ambiguous`, `diagram-dependent` |
| `⏭-C` Contextual | Rule is expressible but depends on an inter-agent or inter-Frame relationship not yet resolved; a later `--enrich` pass targeting the right agent may unblock it | `multi-element` |

For `external-norm` and `procedural`: apply `⏭-S` if the section is genuinely
inaccessible (missing reference standard, procedural with no extractable threshold),
`⏭-C` if it is only temporarily unresolved pending another agent's output.
When uncertain, omit the sub-type tag rather than forcing it.

> These tags appear **only in the README.org `detail` field** of each Deferred entry
> (inside the parentheses) — they do not change the `** ⏭ Deferred` heading format
> and have no impact on webapp parsing.

**Step 2b — Mandatory retry protocol for `too-ambiguous` candidates**

Every section tentatively classified `too-ambiguous` in Step 2a **must** go through
this retry before being written to the coverage report. The goal is to replace a
silent gap with a best-effort rule that documents the uncertainty explicitly inside
the KB, rather than leaving it invisible to all downstream tools.

> **Mode B note:** every section still listed as `too-ambiguous` from a prior pass
> **must** also go through this same retry (the `retry-note` field from the previous
> pass is the starting point — re-read the section in light of any new context brought
> by the current corpus enrichment). Only leave as `too-ambiguous` if the retry still
> yields zero codifiable clauses AND the retry-note is unchanged — update the
> retry-note if the reason evolved.

```
For each section S classified too-ambiguous in Step 2a:

  ATTEMPT 1 — Reformulation
    Re-read S with the question: "Is there at least ONE verifiable condition
    in this section, even if other parts remain ambiguous?"
    — If yes → extract that condition and generate a partial rule (see below).
    — If no  → proceed to ATTEMPT 2.

  ATTEMPT 2 — Structural decomposition
    Split S into its individual sentences / sub-clauses.
    For each sub-clause C:
      — Does C contain a numeric threshold, an enum, or a boolean condition? → codifiable.
      — Does C describe a procedure, a recommendation, or a rationale?       → out-of-scope.
    If at least one codifiable sub-clause exists → generate a partial rule from
    the codifiable sub-clauses only; mark the un-codifiable remainder in
    Constraints & Pitfalls.
    If zero codifiable sub-clauses → RETRY FAILED (proceed to Step 2c).

  RETRY FAILED:
    Classify S as ⏭ Deferred / too-ambiguous in the coverage report.
    Document in the rule catalog of the relevant agent KB org:
      "§<N> — <title> : too-ambiguous after retry — <one sentence explaining
      what made encoding impossible>. Retry on next corpus revision."
    This note makes the gap visible to chorus-review-kb and chorus-strengthen.
```

**Partial rule pattern (used when retry succeeds partially):**

When a section can only be partially codified, generate a rule that:
1. Encodes the verifiable condition(s) as normal `CONDITION`/`ACTION`.
2. Marks every uncertain slot value with `_a_confirmer: 1` on the Frame element
   (same flag used by `chorus-import-project` for uncertain mappings).
3. Sets `motif_*` to a string that states clearly what was confirmed vs. what
   remains uncertain.

```yaml
# CORPUS: §<N> — <standard> — <section title>
# STATUS: partial — uncertain values flagged _a_confirmer (retry Step 2b)
# UNCERTAIN: <one-line description of what could not be encoded>
REGLE:
  NOM: R<NN>-<slug>-partial
  TROUVER:
    var: CHERCHER type_element EGAL <type>
  CONDITION: <verifiable condition from codifiable sub-clauses>
  EXCEPTION: défini $var->{<uncertain_slot>}
  ACTION:
    - FIXER <verdict_slot> = "KO"
    - FIXER motif_<slug> = "<reason — confirmed part> [⚠️ uncertain: <what remains unverified>]"
    - FIXER _a_confirmer = 1
```

> **Effect on downstream tools:**
> - `chorus-check`: element appears in results with `_a_confirmer` flag →
>   classified `❓ uncertain`, not counted as definitive NON_CONFORME.
> - `chorus-review-kb`: rule carries `# STATUS: partial` → flagged for expert
>   review in the HTML viewer.
> - `chorus-strengthen`: partial rule shows up in gap analysis with its
>   UNCERTAIN annotation → generates a targeted enrichment recommendation.
> - Coverage report: section classified ✅ Integrated (partial) rather than
>   ⏭ Deferred — it exists in the KB, even if imperfectly.

**Step 2c — `too-ambiguous` coverage entry (only after Step 2b fails)**

If and only if Step 2b produced zero codifiable sub-clauses, write the section
to the ⏭ Deferred list with:
- reason: `too-ambiguous`
- a mandatory one-line `retry-note` field explaining what made encoding impossible
  (this note is carried forward into every subsequent `--enrich` pass until resolved)

| Section / Article | Reason | retry-note | Suggested action |
|---|---|---|---|
| §<N> — <title> | too-ambiguous | <why retry failed> | Obtain clarification from standard body / await revision |

## `README.org § Coverage` grammar contract (mandatory)

> ⛔ **MANDATORY, non-negotiable grammar — binding even across delegation.**
> This exact structure is consumed mechanically by three downstream systems:
> the `chorus-web` webapp parser (`parseSandboxReadme()` in `chorus.js`),
> `scripts/corpus-inventory.py` (Mode A's Step 1d audit), and this sub-skill's own
> Stability Point check below. **Every single Coverage entry MUST
> be a `**` heading whose first token after the emoji is exactly one of
> `Integrated` / `Deferred` / `Out of scope`** (capitalization matters — the
> parser regex is `^\*{2}\s+[✅⏭⛔]\s+(Integrated|Deferred|Out of scope)`).
> Free-form prose sections (e.g. `* Coverage — <agent> (Mode A pass, <date>)`
> followed by bullet lists like `- Rules generated: N`) are **silently invisible
> to the webapp's Knowledge Base tab** — no error is raised, the data is simply
> never displayed. This is not a stylistic preference, it is a parsing contract.
>
> **This rule applies identically whether you are the top-level agent writing
> `README.org` directly, or a sub-agent spawned to process one agent file in a
> multi-agent pipeline.** If you delegate a `chorus-feed` pass to a sub-agent
> (e.g. via `eca__spawn_agent` for a large multi-agent sandbox), your delegation
> prompt MUST explicitly paste this exact grammar template — do not rely on the
> sub-agent reading this skill file on its own, and do not accept a sub-agent's
> own free-form summary as a substitute for actually writing this block into
> `README.org`. A regression was observed in practice: nearly all agent passes,
> each delegated to a separate sub-agent,
> wrote their own prose-style `* Coverage — <agent>` section instead of this
> grammar — the KB was otherwise complete and correct (all YAML/Helpers valid),
> but entirely unreadable by `chorus-web`'s Knowledge Base tab until manually
> reformatted after the fact.
>
> **INCORRECT (do not do this — prose section, invisible to the webapp):**
> ```org
> * Coverage — agent-fau (Mode A pass, 2026-10-09)
>   - PRIMARY sections processed: 2
>   - Rules generated: 7 (R01-R07)
>   - Deferred: 0
> ```
>
> **CORRECT (grammar-compliant, parsed by chorus-web and corpus-inventory.py):**
> ```org
> ** ✅ Integrated — agent-fau (7 rules / 1 helper)
>    Corpus : corpus/007-agent-fau.md
>    | Section / Article              | Rules generated                    |
>    |------------------------------------+-------------------------------------|
>    | §Part2-ClassFAU-Catalog            | R01-operation-kind-grammar.yml, ... |
> ```
>
> Note the `Corpus : <file>` line (**with a space before the colon** — this is
> the convention used by every existing conformant sandbox and by
> `scripts/corpus-inventory.py`'s matcher; `Corpus:` with no space is also
> accepted by the script but `Corpus : ` is the established convention, keep
> it consistent across a given sandbox).

**Block template** (header line and columns vary slightly by caller — see note below):

```org
* Coverage
  <Generated by chorus-feed Mode A|Last updated by chorus-feed --enrich> — <date>
  Corpus : <corpus-filename>  <(enrichment pass <N>) — Mode B only>

** ✅ Integrated — <agent-slug> (<N> rules / <N> helpers)
   Corpus : corpus/<NNN>-<slug>.md
   | Section / Article corpus              | Artefact généré                              |
   |---------------------------------------+----------------------------------------------|
   | §<ref> — <title>                      | R<NN>-<slug>.yml                             |
   | Table <N> — <title> (HELPER-SOURCE)   | Helper: <function_name>()                    |

** ⏭ Deferred — <agent-slug> (<N> sections)
   | Section / Article     | Reason          | retry-note                        | Suggested new rule / agent       |
   |-----------------------+-----------------+-----------------------------------+----------------------------------|
   | §<N> — <title>        | <reason>        | <blank or Step-2b failure reason> | <RNN-slug or new-agent>          |

** 🧮 Helper-source pending (<N> sections)  ← omit section entirely if N=0
   From Step 1c audit — sections tagged HELPER-SOURCE by chorus-corpus-scoping
   Phase 2, referenced by a PRIMARY rule with a numeric threshold, but no
   Helper function's "# Source corpus:" comment references them yet.
   | Section / Article     | Referenced by (rule)      | Referenced by (agent) |
   |-----------------------+----------------------------+------------------------|
   | §<N> — <title>        | R<NN>-<slug>.yml           | <slug>                 |

** 🔍 UNSCANNED — corpus-inventory.py cross-check (<N> corpus file(s))  ← omit section entirely if N=0
   From Step 1d mechanical audit (count-based, see script docstring) — this
   corpus file's PRIMARY/HELPER-SOURCE marker count exceeds the rows
   accounted for in this Coverage block. Blocks SP1/SP2 until manually
   re-checked (script cannot identify which section is missing).
   | Source file            | PRIMARY+HELPER-SOURCE markers | Rows accounted |
   |-------------------------+-------------------------------+-----------------|
   | <NNN>-<slug>.md         | <n>                            | <n>             |

** ⚠️ CORPUS: unresolved (<N> rules)  ← omit section entirely if N=0
   | Rule file                  | Agent   | CORPUS: line (current)   |
   |----------------------------+---------+--------------------------|
   | rules/<slug>/R<NN>-xxx.yml | <slug>  | TODO — <explanation>     |

** ⛔ Out of scope — <label> (<N> sections)
   | Section / Article     | Reason                                  |
   |-----------------------+-----------------------------------------|
   | §<N> — <title>        | informative / external-norm / procedural|

** Next step
   #+BEGIN_EXAMPLE
   <see Convergence check below — filled in dynamically based on stability point check>
   #+END_EXAMPLE
```

> **Mode A vs Mode B variance (the only differences — everything else above is
> identical between callers):**
> - Header line: `Generated by chorus-feed Mode A` (Mode A) vs. `Last updated by
>   chorus-feed --enrich` + `(enrichment pass <N>)` suffix on the `Corpus :` line (Mode B).
> - `** ✅ Integrated` table: Mode B adds an `Added in pass` column (`Mode A / B<N>`)
>   to each row, tracking which pass introduced each artefact.
> - Mode A writes this block fresh (Step 3, append to `README.org`); Mode B **replaces**
>   the existing block (read first, in Mode B's own Step 1) — see
>   `chorus-feed.md § Phase B4.5` for the atomic single-edit rule governing this
>   replacement (never split across several `eca__edit_file` calls on sub-headings).

> ⚠️ **Delegation:** load `chorus-templates.md § T6` and paste it verbatim into the sub-agent prompt.

## Convergence check (stability point)

After writing/updating `README.org` and displaying the report/delta summary to the
user, determine whether a **KB stability point** has been reached and fill in the
`** Next step` block accordingly.

```
IF ⏭ Deferred-S = 0
   AND ⏭ Deferred-C = 0
   AND 🧮 Helper-source pending = 0
   AND 🔍 UNSCANNED = 0
   AND ⚠️ CORPUS: unresolved = 0 :

  → STABILITY POINT REACHED. Emit in ** Next step:

  #+BEGIN_EXAMPLE
  # KB stable — run coverage audit then test pipeline:
  chorus-review-kb <sandbox-name> --format org
  chorus-check <sandbox-name> <any-projet.json>
  chorus-strengthen <sandbox-name>
  chorus-stress <sandbox-name>
  # Then start convergence loop (see chorus-feed.md § Convergence loop)
  #+END_EXAMPLE

ELSE:

  → Emit in ** Next step the specific pending action (next agent file,
    another --enrich pass, Helper extraction, UNSCANNED resolution, or
    CORPUS: resolution needed).
  Do NOT mention chorus-review-kb — KB is not yet stable.
```

> **Mode A** additionally checks the `* Agent status` table (pre-split mode: are all
> agent files processed?) before reaching this convergence check — see
> `chorus-feed.md § Phase 6.5 Step 4b` for that mode-specific precondition.
> **Mode B** reaches this check directly once its own delta classification (Step 2)
> is complete.

### Validation interactive de la décision SP (Step 4b-checkpoint)

> **Autonomous mode policy** — see `chorus-engine.md § Autonomous mode` for the
> canonical definition. This checkpoint implements that policy.

**Step 1 — Detect AUTONOMOUS_MODE:**

```
AUTONOMOUS_MODE = true  if any of:
  • eca__ask_user absent from the agent's tool catalog
  • running inside a eca__spawn_agent sub-agent
  • --unattended / --batch flag present
  • triggered by an orchestration loop
```

**Step 2a — If AUTONOMOUS_MODE = true:**
```
[checkpoint] Step 4b-checkpoint — skipped (autonomous: <reason>)
  → OUI-default applied: SP decision accepted as-is, ** Next step emitted.
Proceed to next phase.
```

**Step 2b — If AUTONOMOUS_MODE = false (interactive):**

> **WEB-025 (2026-10-26):** `eca__ask_user` fiable dans le terminal webapp.
> Aligne ce checkpoint sur `chorus-strengthen Phase 4-checkpoint` (même fix).

Call `eca__ask_user` to let the operator confirm or override the SP decision
before emitting the `** Next step` guidance:

```
eca__ask_user(
  question: "Step 4b-checkpoint — Stability point : <SP1/SP2/non atteint>.\n\n" +
            "Prochain step suggéré :\n<next-step-text>\n\n" +
            "La décision est-elle correcte ?",
  options: [
    { label: "OUI — continuer", description: "Émettre ** Next step tel quel" },
    { label: "NON — corriger", description: "Indiquez la correction dans votre réponse" }
  ]
)
```

**OUI:** emit `** Next step` as computed. Proceed.
**NON + correction:** apply the correction to the SP decision, then emit `** Next step`.
