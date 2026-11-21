# Sub-skill — chorus-engine-yaml-pitfalls

> **Internal sub-skill** — loaded by `chorus-feed` Phase 4 (after YAML rule generation)
> and by `chorus-audit-rules` as a mechanical pitfall reference.
> Contains the full Checklist Anti-Pitfalls for YAML rules, Frames, and
> multi-specialty architecture.
>
> Trigger: loaded via `eca__read_file` on
> `$ENGINE/agent/skills/chorus-engine-yaml-pitfalls.md`
> from `chorus-feed` Phase 4 or `chorus-audit-rules` Phase 3.

---

### ✅ YAML Rules

- [ ] ⛔ **`CONDITION`/`EXCEPTION` multi-lignes : indicateur `|` obligatoire (ENG-051).**
      Toute `CONDITION:` ou `EXCEPTION:` dont la valeur contient un bloc Perl multi-lignes
      (`do {`, `if (`, variable intermédiaire, etc.) DOIT utiliser l'indicateur de scalaire
      littéral `|`. Sans `|`, le parser YAML tronque la valeur au premier `}` à indentation
      zéro → `codeRule()` reçoit un Perl syntaxiquement invalide → retourne `undef` → la règle
      se charge (comptée dans `_RULES`) mais ne se déclenche **jamais** (aucun message d'erreur).
      ```yaml
      # ⛔ CASSÉ         CONDITION: do {   ← } fermant tronqué par le parser YAML
      # ✅ CORRECT       CONDITION: |
      #                    do {
      #                      ...
      #                    }
      ```
      Détection : `chorus-check Phase 1.5 Step 5n` — `grep -rnE "^CONDITION: [^|'\"]" rules/`.
- [ ] ⛔ **`type_element` — canonical slot name:** the slot identifying the element type is
      **always** named `type_element` in every `FIND`/`CHERCHER` `attribut:` that routes by
      element type. Never `element_type`, `type`, `kind`, or any other variant.
      A mismatch with the project JSON key (`"type_element"`) causes a SOLVED pipeline with
      **all elements unprocessed** — no error, no warning, 0 processed frames.
      This rule applies to every YAML rule in every sandbox and every `chorus-feed` run.
- [ ] **Header present** — every generated rule starts with the structured comment header (§ Rule Documentation Standard). Language matches the corpus (English or French).
- [ ] ⛔ **Every rule MUST push `_rule_trace` at the top of its `ACTION`/`EFFET`, before
      any other `set()` — this is mandatory, not an opt-in convention.**
      ```yaml
      ACTION: |
        my $trace = $f->get('_rule_trace') // [];
        push @$trace, { rule_id => '<rule-id-from-RULE:-field>', corpus_ref => '<short CORPUS: summary>' };
        $f->set('_rule_trace', $trace);
        # ... rest of the rule's business logic ...
      ```
      `rule_id` = the exact value of the rule's own `RULE:`/`REGLE:` field (already
      lowercase in every generated rule). `corpus_ref` = a short summary derived from
      the rule's own `# CORPUS:` header line (not the full sentence).
      **Observed incident:** all rules across multiple
      agents were generated without this block — `run.pl`'s JSON report and
      `chorus-check --explain`'s "rule chain" column were silently empty for every
      element, for the entire lifetime of the sandbox (SP1 reached, `chorus-strengthen`
      run, dozens of fixes applied — nobody noticed `_rule_trace` was simply never
      written, because the degradation is 100% silent: no error, no warning, no JSON
      key, nothing printed). Retrofitting it required editing all 57 `.yml` files
      after the fact. Treat this checklist item exactly like "Header present" or
      "CORPUS line traceable" above — resolve it at generation time, never leave it
      for a later audit to catch.
- [ ] ⛔ **ENG-039 — Every rule whose EXCEPTION is `defined $f->{output_slot}` MUST write
      `output_slot` in ALL branches of its ACTION, including the "insufficient data" branch.
      A `return 0` without writing the output slot leaves the EXCEPTION permanently false
      → the rule re-fires every cycle until `_MAX_ITER` is reached (silent infinite loop).**

      ```yaml
      # ⛔ WRONG — return 0 without writing output_slot
      } else {
          return 0;   # EXCEPTION remains false → re-fire every cycle
      }

      # ✅ CORRECT — write output_slot in every branch
      } else {
          $f->set('output_slot',       '_a_confirmer');
          $f->set('non_conformity_motif', 'Insufficient data: slot_a, slot_b and slot_c all absent');
          return 1;
      }
      ```

      **Corollary — `_rule_trace` push before `return 0`:** if the rule pushes to
      `_rule_trace` before the data-check block, the push fires every re-fire cycle →
      hundreds of duplicate entries in the trace. Always guard the push with
      `unless (grep { ($_->{rule_id} // '') eq '<rule-id>' } @$trace)`, OR move it
      inside the successful branch only. (ENG-039 Bug 3)

- [ ] ⛔ **Every rule that can resolve a verdict slot (`*_ok`/`*_conforme`/`statut_conformite`,
      etc.) to a FAILING value MUST also write an explicit `non_conformity_motif`
      (English corpus) / `motif_non_conformite` (French corpus) in the same branch —
      mandatory, not optional.**
      ```yaml
      ACTION: |
        # ... compute $required, $as_built ...
        if ($as_built < $required) {
          $f->set('result_ok', 'NO');
          $f->set('non_conformity_motif', "value ${as_built}<unit> is below the required minimum of ${required}<unit> (§<N>)")
              unless $f->get('non_conformity_motif');   # first writer wins — never overwrite
                                                          # a motif already set by another rule
                                                          # that fired earlier on this Frame
          return 1;
        }
        $f->set('result_ok', 'YES');
        1
      ```
      The guard `unless $f->get('non_conformity_motif')` is mandatory whenever more than
      one rule can write a failing verdict on the same Frame (common pattern — see
      `_rule_trace` entries accumulating across several rules on one element).
      If a rule has several distinct failure branches (different thresholds/causes),
      each branch must write its OWN specific motif — never a single generic motif that
      would hide which condition actually failed.
      **Observed incident (same sandbox, same session):** 8 of the 10 non-conformity
      rules in the coverage test only wrote a binary `*_ok = 'NO'` verdict, with zero
      explanation text — `chorus-check --explain` and the web report view had nothing
      to show beyond a bare `verdict=NO`, even though `_rule_trace` (once retrofitted)
      proved the engine DID know exactly which rule/article caused the failure. A
      `run.pl`-level fallback (deriving a generic motif from the last `_rule_trace`
      entry — see `chorus-templates.md` T5) is a safety net, not a substitute for this
      checklist item: a rule-authored motif can state the actual numeric values
      involved, which a generic fallback never can.

- [ ] ⛔ **ENG-038 — `non_conformity_motif` is required on UNCERTAIN and CONDITIONAL
      verdicts too**, not only on classic `NO`/`NON_CONFORME` failing verdicts.
      The webapp's `elementMotif()` function reads `non_conformity_motif` (and
      `motif_*` fields as a fallback) — it does **not** read `authorization_basis`
      or `raison_non_conformite`. Any rule that sets a verdict the webapp renders as
      non-green without also writing `non_conformity_motif` will show a blank MOTIF
      column in the report view. **Applies to:**
      | Verdict value set by rule | Requires `non_conformity_motif` ? |
      |---|---|
      | `'NO'` / `'NON'` / `'NON_CONFORME'` | ✅ yes — already covered above |
      | `'_a_confirmer'` | ✅ yes — cross-sandbox engine convention; motif explains what data is missing |
      | Any domain-specific partial/conditional string (e.g. `'ecl_required'`, `'conditional'`, `'insufficient_data'` in a copyright sandbox) | ✅ yes — domain values, not engine conventions; the engineer must add `non_conformity_motif` for each |
      | `'YES'` / `'CONFORME'` / `'OUI'` / `'NA'` / `1` | ❌ no — positive / not-applicable verdicts |

      **Aggregate rules** (rules that collect sub-rule verdicts into a final slot)
      must also set `non_conformity_motif` when their aggregate verdict is not
      CONFORME. The canonical pattern is to forward the sub-rule's specific motif:
      ```perl
      # In the aggregate ACTION, after computing $verdict:
      unless ($verdict eq 'CONFORME') {
        # Option A: forward the most specific sub-motif already set
        my ($mk) = grep { defined $e->get($_) } @motif_slot_names;
        $e->set('non_conformity_motif', $mk ? $e->get($mk) : "Issues in: " . join(', ', @failing_slots));
        # Option B: alias an existing motif_<aspect> slot (simpler when only one sub-rule)
        $e->set('non_conformity_motif', $e->get('motif_transfer_valid'))
          unless $e->get('non_conformity_motif');
      }
      ```
      Domain-specific `motif_<aspect>` fields (e.g. `motif_governance`,
      `motif_transfer_valid`) are still useful as detailed per-aspect explanations —
      they complement `non_conformity_motif`, they do not replace it.
- [ ] **CORPUS line traceable** — `CORPUS:` references the exact standard article (§N) that
      justifies the rule. This line is **mandatory and must be resolved before the session ends**:
      - ✅ `# CORPUS: §4.2 — NF DTU 31.2 — Porteur intermédiaire` — fully resolved, preferred form.
      - ⚠️ `# CORPUS: TODO — <one sentence explaining why the source is not yet identified>` —
        temporary placeholder only; acceptable within the same generation session if the
        corpus reference will be resolved before the session closes. A `TODO` left at session
        end is a **generation defect** — it is detected and reported by Phase 6.5 Step 1b
        of `chorus-feed` and flagged as `Orphan` by `chorus-review-kb`.
      - ⛔ Absent `CORPUS:` line — treat as a generation defect equivalent to `TODO`; add
        the line with `TODO` immediately rather than leaving the header incomplete.
- [ ] **Always** end `ACTION` with a truthy value (`1` or truthy expression)
- [ ] **`filtre` in `FIND`: always use `$_`, never `$f`** — `$f` (scope variable) is only defined inside `ACTION`/`EFFET`. Using `$f->` in `filtre` causes a compilation crash (`Global symbol "$f"`).
      **Prefer `$_->get('slot')` over `$_->{slot}`** — `$_->{slot}` only sees directly-stored scalars; it misses `_DEFAULT` on prototypes and slots inherited via `_ISA`.
      `$_->{slot}` is acceptable only for `type_element` (always a direct scalar from `Feed.pm → new(%$json_hash)`) or slots guaranteed to be plain scalars written by the current rule.
- [ ] **Multi-level slot access in `ACTION`/`EFFET`: prefer `$var->get('a b c')` over `$var->a->b->c`** —
      `get('a b c')` is **one** call: `$SELF` stays the rule-Frame (`$var`) throughout the traversal.
      The chained form `->a->b->c` makes **three** AUTOLOAD calls: `$SELF` shifts to each
      intermediate sub-frame, silently breaking any `_NEEDED` or `_DEFAULT` coderef that
      reads `$SELF` to reach the top-level domain object.
      → See `chorus-frame-advanced.md § get('a b c') vs ->a->b->c`.
- [ ] **`CONDITION` must test data presence, not conformance** — a CONDITION that tests a business result (e.g. `$f->get('result') eq 'OK'` or a Helper call returning a pass/fail value) silently blocks all non-conforming Frames: the rule never fires on them, so no slot is ever set → downstream agents never see those Frames → silent pipeline gap. Always restrict `CONDITION` to testing slot presence (`defined $f->get('slot')`), type routing (`$f->get('type') eq '...'`), or the existence of prerequisite computed slots. Move the conformance test into `ACTION`/`EFFET`, which sets the `_ok` slot to `'OUI'` or `'NON'`.
      ```yaml
      # ⛔ WRONG — non-conforming Frames silently skipped; slot never set
      CONDITION: |
        SomeHelper->is_valid($f->get('val'), SomeHelper->min_required($f->get('type')))
      # ✅ CORRECT — always fires when data is present; get() traverses _ISA and _DEFAULT
      CONDITION: "defined $f->get('val') && defined $f->get('type')"
      # ACTION then computes and sets 'result_ok' to 'OUI' or 'NON'
      ```
- [ ] **Conditional ACTION without `else`**: if the `if` modifies nothing and returns `1` → infinite loop until `_MAX_CYCLES`.
      ```yaml
      # ⛔ WRONG — infinite loop if condition never true
      ACTION: |
        if ($p->get('val') > 5) { $p->set('flag', 'KO') }
        1
      # ✅ CORRECT
      ACTION: |
        if ($p->get('val') > 5) { $p->set('flag', 'KO'); return 1 }
        0
      ```
      > Invisible on a sandbox (6 frames), critical at real scale (300 frames × 40 rules).
- [ ] ⛔ **Aggregate rule waiting on an "expected children" list (`elements` /
      `composants_requis` / similar) MUST bound its wait — never `return 0`
      forever when an expected sibling Frame simply does not exist in the
      project.** A common aggregation pattern (1 parent Frame expects N child
      Frame ids, computed earlier by a levelling/catalog rule) resolves each
      expected id against the live Frame registry (`fmatch`) and defers
      (`return 0`, retried next cycle) while any expected id has no matching
      Frame yet. This is correct **only** for "not yet processed" — the engine
      has no way to tell "not yet loaded" apart from "will never exist in this
      project" (e.g. a minimal/smoke-test project that supplies only 3 of a
      component's 13 expected sub-elements). Left unbounded, the rule
      `return 0`s on every cycle until `_MAX_CYCLES`, each cycle re-scanning
      the full Frame registry — costly, and the parent's own aggregate slot
      (read by a downstream phase-done/termination rule) never gets set,
      risking the same whole-pipeline non-convergence class described in
      `chorus-feed.md` § "Mandatory check before authoring any CONDITION/
      EXCEPTION on a cross-agent targeting slot".
      ```yaml
      # ⛔ WRONG — waits forever if an expected id never appears in the project
      ACTION: |
        my @expected_ids = split(/,/, $c->get('elements') // '');
        my %by_id = map { $_->get('type_element') => $_ } Chorus::Frame::fmatch(slot => 'type_element');
        for my $id (@expected_ids) {
          return 0 unless $by_id{$id} && defined $by_id{$id}->get('child_ok');
        }
        $c->set('parent_declared', 1);
        1

      # ✅ CORRECT — bounded wait, explicit motif once the bound is hit
      ACTION: |
        my @expected_ids = split(/,/, $c->get('elements') // '');
        my %by_id = map { $_->get('type_element') => $_ } Chorus::Frame::fmatch(slot => 'type_element');
        use constant MAX_WAIT_CYCLES => 5;
        my $waited = ($c->get('_decl_wait_cycles') // 0) + 1;
        my (@missing, @pending);
        for my $id (@expected_ids) {
          my $elt = $by_id{$id};
          if (!$elt) { push @missing, $id; next }
          push @pending, $id unless defined $elt->get('child_ok');
        }
        if (@pending && $waited < MAX_WAIT_CYCLES) {
          $c->set('_decl_wait_cycles', $waited);
          return 0;   # at least one sibling exists but isn't scored yet — genuinely transient
        }
        if (@missing || @pending) {
          $c->set('parent_declared', 0);
          $c->set('non_conformity_motif',
            "missing or unscored: " . join(',', @missing, @pending))
            unless $c->get('non_conformity_motif');
          return 1;   # stop waiting — this will never resolve on its own
        }
        my $all_ok = !grep { !$by_id{$_}->get('child_ok') } @expected_ids;
        $c->set('parent_declared', $all_ok ? 1 : 0);
        1
      ```
      **Incident:** this exact unbounded pattern,
      copy-pasted identically across several SAR class agents' own
      `component-declared-aggregate` rule, left a large fraction of elements permanently
      `(unprocessed)` against a minimal test project — not a crash, not a
      warning, just `return 0` forever on every affected component. Confirmed by
      testing each agent in isolation (fast, correct) vs. the full 21-agent
      pipeline (very slow, incomplete) — the aggregate rule's own missing-sibling
      case was the actual root cause, not agent interaction. Fixed by adding the
      bounded-wait pattern above to all 7 copies.
- [ ] ⛔ **Bounded-wait `!@elements` branch — `return 0` causes immediate
      fixpoint when sub-elements will NEVER appear in this project.** The
      pattern above correctly uses `return 0` when `@pending && waited <
      MAX_WAIT_CYCLES` (sub-elements exist but are still unscored — genuinely
      transient). But many aggregate rules ALSO apply the same bounded-wait to
      the `!@elements` case (no sub-elements at all). This is a distinct and
      more dangerous failure mode:
      - The engine's inner loop stops after the **first** cycle where every
        rule returns 0 or is EXCEPTION-blocked (fixpoint). With `return 0` as
        the **only** action in a cycle, fixpoint is declared immediately after
        cycle 1 — `_decl_wait_cycles` is incremented to 1, the engine stops,
        and `_decl_wait_cycles` never reaches `MAX_WAIT_CYCLES`. The aggregate
        slot is NEVER set.
      - This is invisible in long-running sessions where `pipeline_solved=false`
        (engine always runs `_MAX_CYCLES` cycles, giving the rule many chances
        to accumulate). It only surfaces when a TERMINAL rule fires early
        (pipeline converges quickly), cutting the inner loop before the bounded
        wait completes.

      ```yaml
      # ⛔ WRONG — return 0 on !@elements causes fixpoint, _decl_wait_cycles
      # never reaches MAX_WAIT_CYCLES, aggregate slot never set
      ACTION: |
        my @elements = grep { ... } Chorus::Frame::fmatch(slot => 'type_element');
        use constant MAX_WAIT_CYCLES => 5;
        my $waited = ($c->get('_decl_wait_cycles') // 0) + 1;
        if (!@elements) {
          if ($waited < MAX_WAIT_CYCLES) {
            $c->set('_decl_wait_cycles', $waited);
            return 0;   # ⛔ fixpoint after first cycle — never accumulates
          }
          $c->set('component_declared', 1);
          return 1;
        }
        ...

      # ✅ CORRECT — set immediately when no sub-elements exist; only use
      # bounded wait for the case where sub-elements exist but aren't scored
      ACTION: |
        my @elements = grep { ... } Chorus::Frame::fmatch(slot => 'type_element');
        use constant MAX_WAIT_CYCLES => 5;
        my $waited = ($c->get('_decl_wait_cycles') // 0) + 1;
        if (!@elements) {
          # No sub-elements exist for this component — set immediately.
          # DO NOT apply a bounded-wait here: if sub-elements never appear in
          # the project (e.g. parent-level _EXT components), return 0 would
          # cause premature fixpoint (engine stops after 1 non-productive cycle).
          my $trace = $c->get('_rule_trace') // [];
          push @$trace, { rule_id => 'component-declared-aggregate', corpus_ref => '...' };
          $c->set('_rule_trace', $trace);
          $c->set('component_declared', 1);
          return 1;
        }
        my $pending = grep { !defined $_->{child_ok} } @elements;
        if ($pending && $waited < MAX_WAIT_CYCLES) {
          $c->set('_decl_wait_cycles', $waited);
          return 0;   # ✅ safe: sub-elements DO exist, wait is genuinely transient
        }
        ...
      ```
      **Rule of thumb:** `return 0` on `!@elements` is only safe when the engine
      is guaranteed to run many more cycles regardless (e.g. `pipeline_solved`
      will never fire, or `_MAX_CYCLES` is large and the pipeline never has a
      TERMINAL shortcut). As soon as any pipeline path includes a TERMINAL rule
      that may fire early, `return 0` on `!@elements` silently prevents scoring.
      **Use `return 1` + immediate set whenever sub-elements cannot be expected
      to arrive later.**

      **Incident:** several SFR `_EXT` parent-level
      components (e.g. `FCO_NRO_EXT.2`, `FCS_CKM_EXT.1`, `FDP_CER_EXT.1`)
      went `(unprocessed)` after a TERMINAL rule started firing earlier (EAL
      package Frame added to project). `_decl_wait_cycles=None` confirmed the aggregate rule
      fired zero times despite all other logic being correct. Fixed by removing
      the wait on `!@elements` entirely in all affected SFR aggregate rules.
- [ ] ⛔ **A pipeline-completion gate rule reading multiple BOARD flags MUST
      declare those flags in its `CONDITION`, not just in its `ACTION`.** A
      common pattern: rule R fires when "all N upstream BOARD flags are
      defined", then sets a downstream aggregation slot. If R has no
      `CONDITION` (or only `EXCEPTION: defined $w->{result_slot}`), it fires
      on the **first engine cycle** — before any upstream agent has published
      its flags. It evaluates all flags as `undef`, sets `result_slot=0`,
      and is **permanently blocked** by Pattern 1 (`EXCEPTION: defined →
      true`). None of the N upstream flags ever unblocks it.
      ```yaml
      # ⛔ WRONG — fires cycle 1, evaluates all flags as undef → result=0 → blocked
      RULE: wait-for-all-phases-done
      FIND:
        w: { attribut: besoin_conformite }
      EXCEPTION: defined $w->{pipeline_complete_ok}
      ACTION: |
        my $ok = ( defined $SELF->BOARD->{phase_a_done}
                && defined $SELF->BOARD->{phase_b_done} ) ? 1 : 0;
        $w->set('pipeline_complete_ok', $ok);
        1

      # ✅ CORRECT — CONDITION gates the rule until all BOARD flags are available
      RULE: wait-for-all-phases-done
      FIND:
        w: { attribut: besoin_conformite }
      EXCEPTION: defined $w->{pipeline_complete_ok}
      CONDITION: >
        defined $SELF->BOARD->{phase_a_done} &&
        defined $SELF->BOARD->{phase_b_done}
      ACTION: |
        $w->set('pipeline_complete_ok', 1);   # CONDITION already guarantees both are defined
        1
      ```
      **Incident:** `conformance-ctrl/R01`
      (`wait-for-pipeline-complete`) had no `CONDITION` — it fired in cycle 1,
      set `pipeline_complete_ok=0` (4 BOARD flags absent), and was blocked by
      Pattern 1 forever. Downstream R02→R03→R04 (which all gate on
      `pipeline_complete_ok=1`) never fired; `pipeline_solved=false` for the
      entire pipeline lifetime. Fixed by adding a `CONDITION` checking the 4
      BOARD flags — R01 then fires only once all are defined, guaranteeing
      `pipeline_complete_ok=1`.
- [ ] ⛔ **`fmatch(slot => '...')` inside an `EXCEPTION` MUST be filtered down to
      the agent's own targeted Frame family before testing any domain slot —
      an unfiltered `fmatch` call returns EVERY Frame in the project carrying
      that slot, not just this agent's own.** This is distinct from the
      already-documented "never use global `fmatch` in `FIND`" rule (which
      causes an infinite loop) — `fmatch` in `EXCEPTION`/`CONDITION` is
      structurally safe (the rule itself still only runs once per cycle per
      scope combination), but an unfiltered scan silently makes the guard
      permanently true: Frames of unrelated types will virtually never carry
      this agent's own aggregate slot, so a check like "is there any Frame
      still missing `my_agent_result`?" always finds one (any SFR element,
      any other agent's component, …), blocking the rule forever.
      ```yaml
      # ⛔ WRONG — fmatch scans the WHOLE project; any unrelated Frame
      # missing sar_component_declared (which it never has, by design)
      # permanently blocks this agent's own phase-done publication
      EXCEPTION: scalar(grep { !defined $_->{sar_component_declared} } Chorus::Frame::fmatch(slot => 'type_element')) > 0

      # ✅ CORRECT — filter to this agent's own Frame family FIRST,
      # exactly like the agent's own FIND filtre
      EXCEPTION: 'scalar(grep { !defined $_->{sar_component_declared} } grep { $_->{type_element} =~ /^ACO_(COR|DEV|REL|CTT|VUL)\.\d+$/ } Chorus::Frame::fmatch(slot => "type_element")) > 0'
      ```
      **Incident:** this exact unfiltered
      pattern, copy-pasted across all SAR class agents' own
      `mark-phase-done-and-terminate` rule, meant none of them ever published
      their `*_phase_done` BOARD flag on any project — the downstream
      aggregation agent (`conformance-ctrl`) never saw its own completion
      gate satisfied, never reached a genuine `solved()`. The 11 SFR class
      agents' equivalent rules were correctly filtered from the start —
      comparing the two templates side by side (same agent position in the
      pipeline, same rule intent) is what exposed the missing `grep` in the
      SAR copies.
- [ ] ⛔ **A rule's `FIND.attribut` must name a slot that genuinely exists on
      the Frames it targets — verify against the actual project data model,
      never assume from the rule's own INPUTS-header prose.** A `FIND` whose
      `attribut:` references a slot no project Frame ever carries makes the
      rule permanently dormant: zero candidates, `_APPLY` never runs, no
      error, no warning — indistinguishable from "this rule simply never
      needed to fire yet" until a downstream rule's own `CONDITION` on this
      rule's output slot is traced back to the source.
      **Incident:** `sar-eal-package`'s own
      `eal-claim-grammar` rule targeted `attribut: eal_claim` — a slot that
      does not exist anywhere in the project's data model (the EAL claim
      string is carried directly as the Frame's own `type_element`, e.g.
      `"EAL4"` or `"EAL4 augmented with ALC_FLR.3"`, confirmed by every
      *downstream* rule in the same agent correctly reading
      `eal_claim_grammar_ok` rather than `eal_claim`). The rule never fired
      on any project — not a crash, just permanently zero candidate Frames —
      stalling the entire downstream chain (R03's own `CONDITION` on
      `eal_claim_grammar_ok`, then R06's BOARD publication, then
      `conformance-ctrl`'s own completion gate). Caught by comparing the rule
      against its own sibling rules in the same agent (which already read the
      *correctly*-named derived slot) and against the project's own raw JSON
      data for that Frame type.
- [ ] **Always** add `EXCEPTION` for idempotence — **two patterns:**
      - **Pattern 1** (`defined $var->{slot_pose}`) for classification rules — "first writer wins".
        Once any rule writes the slot, all rules with the same guard are blocked on this Frame.
      - **Pattern 2** (`($var->{slot_pose} // "") eq "<veto_value>"`) for veto/exclusion/override rules
        that must fire even after a sibling has written the slot in a previous cycle.
      ⚠️ **`$var->{slot}` is intentional here** (not a bug, unlike reads in ACTION).
      It tests "has `set()` explicitly written this slot on this Frame?" — not "does any value exist?".
      Using `$var->get('slot')` would also block the rule when a prototype `_DEFAULT` provides a value,
      meaning the rule would never compute and write the actual `_VALUE`. Keep `$var->{slot}` in
      EXCEPTION guards; use `$var->get('slot')` everywhere else.
      → Full decision table: `chorus-engine-yaml.md § CONDITION vs EXCEPTION`
- [ ] ⛔ **Use `|` (literal block scalar) for multi-line `ACTION`, never `>`.**
      `ACTION: >` (folded scalar) collapses **all newlines to spaces** before eval. A comment
      on its own line followed by an `if` statement becomes a single line:
      `# comment if (condition) {` — the entire `if` is now commented out. No syntax error;
      the rule silently does nothing. The resulting runtime error is `syntax error near "} if"`
      or a missing closing brace — far removed from the actual cause.
      ```yaml
      # ⛔ WRONG — > folds newlines; comment swallows the if statement
      ACTION: >
        my $x = $e->get('price');
        # Floor check: price <= 0 → skip
        if ($x > 0) { $e->set('result', 'OK') }
        1
      # ✅ CORRECT — | preserves newlines; comment stays on its own line
      ACTION: |
        my $x = $e->get('price');
        # Floor check: price <= 0 -> skip
        if ($x > 0) { $e->set('result', 'OK') }
        1
      ```
- [ ] ⛔ **Never `use Module::Name qw(...)` inside `ACTION`/`EFFET`.**
      `use` is a **compile-time directive** — it runs at Perl parse time, not eval time.
      Inside a YAML `ACTION` block (which is `eval`'d at runtime by `loadRules`), `use`
      causes `Bareword "use" not allowed` or silently fails. Inject helpers via typeglob
      in the Agent's `build()` BEFORE `loadRules()` — they are then available to all rules
      of that agent at eval time. See § Multi-Specialty Architecture above.
      ```yaml
      # ⛔ WRONG — use inside ACTION: compile-time statement in runtime eval
      ACTION: |
        use MyAgent::Helpers qw(compute_fee);
        my $fee = compute_fee($e->get('price'));
      # ✅ CORRECT — helper injected in Agent.pm build() before loadRules()
      ACTION: |
        my $fee = compute_fee($e->get('price'));   # available via typeglob
      ```
- [ ] ⛔ **One rule per YAML file. Never use `---` document separator in a rule file.**
      `Chorus::Engine::loadRules()` calls `YAML::LoadFile()` which reads **only the first
      YAML document** from each file. Any rule after a `---` separator is **silently ignored**
      — no error, no warning, no trace. The missing rules are discovered only at runtime
      when Frames they should process remain unprocessed.
      Rule naming convention: `R01-<slug>.yml`, `R02-<slug>.yml` — one file per rule,
      alphabetical order = load order.
- [ ] ⛔ **Pipeline-done rules: use `fmatch(slot => '<agent_output_slot>')`, not `fmatch(slot => 'type_element')`.**
      A pipeline-done gate that uses `fmatch(slot => 'type_element')` to check that all
      Frames are processed will find **every** Frame type in the sandbox (use_of_work,
      collective_management_organisation, remuneration_obligation, etc.) and check them
      all for `protection_status` — which only protected_object Frames ever receive.
      The gate never fires. Use the agent's own output slot instead:
      ```yaml
      # ⛔ WRONG — finds all 7 Frame types; non-protected ones never get protection_status
      ACTION: |
        my @all = fmatch(slot => 'type_element');
        return 0 if grep { !defined $_->{protection_status} } @all;
        $SELF->BOARD->{'protection_pipeline_done'} = 1; 1
      # ✅ CORRECT — only finds protected_object Frames (the ones R01 classified)
      ACTION: |
        my @protected = fmatch(slot => 'object_type');   # set by R01 on protected_objects only
        return 0 if grep { !defined $_->{protection_status} } @protected;
        $SELF->BOARD->{'protection_pipeline_done'} = 1; 1
      ```
- [ ] Name files `R01-`, `R02-` to control loading order
- [ ] `filtre` in `FIND` to narrow scope **before** `_APPLY`

### ✅ Frames

- [ ] ⛔ **Never `$f->{slot} = $val`** — use `$f->set('slot', $val)` — direct assignment bypasses `%REPOSITORY` → `fmatch` returns 0 Frames → **silent** pipeline break
      ```perl
      # ⛔ WRONG — slot invisible to fmatch (pipeline silently broken)
      $f->{besoin_conformite} = 1;
      # ✅ CORRECT
      $f->set('besoin_conformite', 1);
      ```
- [ ] ⛔ **Never `$f->{slot}` for READS in ACTION/EFFET/CONDITION or Helpers.pm** — use `$f->get('slot')` or `$f->slot`.
      `$f->{slot}` bypasses the full valuation chain: no `_DEFAULT`, no `_NEEDED`, no `_ISA` traversal.
      Works by coincidence for plain scalar slots, silently wrong for prototyped/lazy/inherited slots.
      ```perl
      # ⛔ WRONG — misses _DEFAULT on prototype, _NEEDED, inherited slots
      my $type = $p->{type_element};
      my $val  = $w->{height_m} // 0;
      my $cond = $f->{masonry_condition} // 'A';   # _DEFAULT => 'A' on prototype → gets hashref
      # ✅ CORRECT — full valuation chain
      my $type = $p->get('type_element');
      my $val  = $w->get('height_m') // 0;
      my $cond = $f->get('masonry_condition') // 'A';
      ```
      **Legitimate exceptions:** EXCEPTION idempotence guards (`defined $f->{slot}` — intentional, see above),
      `run.pl` display (result slots are plain scalars), and Engine system slots (`$SELF->{_KEY}`, etc.).
      → Full decision table: `chorus-frame-advanced.md § $f->{slot} vs $f->get('slot') — Read semantics`
- [ ] Never use `delete $f->{slot}` — use `$f->delete('slot')`
- [ ] Never name a domain slot with a `_UPPERCASE` prefix (reserved for the system)
- [ ] In `_AFTER`: capture `$SELF` **before** any call to `set()` on another Frame:
      ```perl
      # ⛔ WRONG — $SELF overwritten by internal set()
      _AFTER => sub { $other->set('x', $SELF->val) }
      # ✅ CORRECT
      _AFTER => sub { my $ctx = $SELF; $other->set('x', $ctx->val) }
      ```

### ✅ Multi-Specialty Architecture

- [ ] **1 specialty = 1 agent = 1 YAML directory = 1 optional Perl module**
- [ ] The implicit pipeline: each agent reads the slot set by the previous one
- [ ] **Perl helpers — mandatory typeglob injection into `Chorus::Engine` before `loadRules()`**:
      ```perl
      use MyAgent::Helpers qw(mon_helper);
      { no strict 'refs'; *{'Chorus::Engine::mon_helper'} = \&mon_helper; }
      $agent->loadRules("$base/rules/mon-agent");
      ```
      Without this: `Undefined subroutine &Chorus::Engine::mon_helper`.
      ⛔ **Never put `use MyAgent::Helpers` inside a YAML `ACTION` block** — see YAML Rules checklist above.
- [ ] ⛔ **ENG-032 — Every Helper sub name MUST be prefixed with the agent slug**
      (`<slug>_<name>`, hyphens → underscores). The `Chorus::Engine` typeglob namespace
      is shared across ALL agents in the sandbox — a name collision silently overwrites
      the first agent's closure with no warning, producing wrong verdicts and an
      undiagnosable `max iterations` stall (see pitfall above).
      ```perl
      # ⛔ WRONG — collision-prone: any other agent could define the same name
      sub class_family_completion_status { ... }
      *{'Chorus::Engine::class_family_completion_status'} = \&class_family_completion_status;

      # ✅ CORRECT — slug-prefixed, structurally unique across the sandbox
      sub adv_agd_alc_family_completion_status { ... }
      *{'Chorus::Engine::adv_agd_alc_family_completion_status'} = \&adv_agd_alc_family_completion_status;
      ```
      The corresponding YAML `ACTION` calls must match the prefixed name exactly.
      `chorus-check` Step 5m enforces this mechanically before any infrastructure generation.

---
