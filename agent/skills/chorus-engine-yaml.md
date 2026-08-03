# Chorus::Engine — YAML Authoring Reference

> **Authoritative source for YAML authoring.**
> This file owns its sections — do not duplicate them in `chorus-engine.md`.
>
> Loaded by: `chorus-feed` (§0 Prerequisites)
> For direct Perl work in `$ENGINE`: load this file + `chorus-engine-infra.md`
> Scope: everything needed to write correct YAML rules and Helpers.pm.
> Not covered here: Perl infrastructure (Feed, Agent, Expert, run.pl) → `chorus-engine-infra.md`
> Not covered here: Collection::List / Collection::Filter → `chorus-engine.md`

---

## Frame essentials for YAML authors

### `$SELF` and `fmatch()`

**`$SELF`** = current context, available in any slot of type `sub { }` and in YAML EFFETs:

```perl
# In a Perl frame:
my $f = Chorus::Frame->new(
    label => sub { "I am " . $SELF->name },
    name  => 'Chorus',
);
```

**`fmatch()`** — slot-based Frame selection via `%REPOSITORY`:

```perl
my @c = fmatch(slot => 'couleur');                        # all Frames with slot 'couleur'
my @r = fmatch(slot => ['couleur', 'score']);             # intersection
my @r = fmatch(slot => 'couleur', from => \@subset);      # restricted search space
```

> ⛔ A Frame is only visible to `fmatch` if its slot was registered via `$f->set('slot', val)`.
> Direct assignment `$f->{slot} = val` bypasses registration → `fmatch` returns 0 Frames → **silent pipeline break**.

### Reading and writing slots

```perl
$f->get('slot')        # read — traverses inheritance chain
$f->slot               # shorthand read
$f->set('slot', $val)  # write — registers in %REPOSITORY → visible to fmatch
$f->delete('slot')     # delete — unregisters from %REPOSITORY
```

### Reserved system slots — never use as domain slot names

`_KEY` `_PARENT_KEY` `_ISA` `_VALUE` `_DEFAULT` `_NEEDED` `_BEFORE` `_AFTER` `_REQUIRE` `_NOFRAME` `_SERIALIZE`

> **⚠️ Language rule — domain slot names:** all domain slot names (i.e. all slots **except**
> reserved system slots above and the invariant `type_element`) must be named in the **corpus language**.
> French corpus → `montant_porteur`, `classe_bois`, `besoin_conformite`.
> English corpus → `bearing_member`, `wood_class`, `conformance_need`.
> This applies to `FIND`/`CHERCHER` `attribut:` values, `ACTION`/`EFFET` slot reads/writes,
> and `PREMISES`/`PREMISSES` entries.
> → See canonical rule in `chorus-engine.md § Canonical Language Rule`.

---

## Engine — Rule triggering

**Rule structure (pure Perl — what YAML compiles to):**

```perl
$agent->addrule(
    _ID    => 'nom-unique',
    _SCOPE => {
        var => sub { [ fmatch(slot => 'slot_cible') ] },
    },
    _APPLY => sub {
        my %opts = @_;
        return unless <condition>;
        # ... effets ...
        return 1;
    },
);
```

**Inference loop:** `loop()` calls `applyrules()` as long as at least one rule returns true.
Safety: `_MAX_CYCLES` (default 10,000) → warning + stop if exceeded.

**Flow controls in YAML ACTION — use `$SELF` (never `$agent`):**

| `$SELF->method()` | Effect |
|---|---|
| `$SELF->cut()` | exits scope loops → next rule (same agent) |
| `$SELF->last()` | exits rules loop → next agent |
| `$SELF->replay()` | restarts from 1st rule of this agent |
| `$SELF->replay_all()` | restarts from 1st agent |
| `$SELF->solved()` | `BOARD->{SOLVED} = 'Y'` → immediate stop |
| `$SELF->failed()` | `BOARD->{FAILED} = 'Y'` → immediate stop |

> ⛔ `$agent` is **not** in scope inside a YAML ACTION eval → `Global symbol "$agent"` crash.
> Always use `$SELF` for flow control in `.yml` files.
>
> ⚠️ `$agent` is **not** in scope in a YAML ACTION — use `$SELF` for flow control.

---

## Implicit Slot Pipeline

Agent chaining via the slot targeted in `FIND`:

| Agent | `FIND.attribut` | Sets the slot |
|---|---|---|
| Specialty 1 | `slot_brut` | `slot_enrichi` |
| Specialty 2 | `slot_enrichi` | `slot_calcule` |
| Specialty 3 | `slot_calcule` | `statut` |
| Ctrl | `slot_cle` (+ check `statut`) | calls `solved()` |

> **Golden rule:** each agent looks for a slot that only the previous agent can have set.
> This guarantees execution order without explicit coupling.

---

## Inter-Frame Navigation in ACTION / EFFET

> **See also:** `chorus-engine-infra.md § 3. Inter-Frame Relationships` for the
> full Feed.pm implementation (2-pass, `%REF_FIELDS`, prototype catalogs).
> This section covers the YAML-side conventions only.

### Navigating a slot→Frame link

When a frame carries a slot that holds a reference to another Frame (Pattern A —
structural link), two patterns depending on whether the link is optional:

```yaml
ACTION: |
  # ── Option A: link optional — fallback to direct slot (backward-compatible)
  # Use when the same rule must work on project files with and without the link.
  # Replace 'link_slot', 'remote_slot', 'local_fallback_slot' with actual names.
  my $linked = $w->get('link_slot');
  my $val    = $linked
      ? ($linked->get('remote_slot')  // 0)
      : ($w->{local_fallback_slot}    // 0);
  # e.g.: my $sup = $w->get('supports');
  #       my $h   = $sup ? ($sup->get('height_m') // 0) : ($w->{height_m} // 0);
  1
```

```yaml
ACTION: |
  # ── Option B: link mandatory — hard skip if absent
  # Use only when the link is architecturally guaranteed.
  my $sup = $w->get('supports')
      or do { warn "R05: no 'supports' link on $w->{id}\n"; return 0 };
  my $h = $sup->get('height_m') // 0;
  # ... checks using $h
  1
```

> ⛔ **Never write to a linked Frame from a rule:**
> `$w->get('supports')->set('slot', val)` creates side effects on frames
> processed by other agents — invisible and hard to debug.  Read only.

### Reading inherited thresholds via `_ISA`

When a frame inherits from a prototype (Pattern B — `_ISA`), read thresholds
directly via `get()` — the inheritance chain is traversed transparently:

```yaml
ACTION: |
  my $cond    = $w->{masonry_condition} // 'A';
  my $min_str = $w->get("min_str_$cond");   # traverses _ISA → prototype

  unless (defined $min_str) {
      $w->set('strength_ok', 'YES');   # no numeric minimum for this spec
      return 1;
  }
  # ... comparison
  1
```

Dynamic slot names (`"min_str_$cond"`) work with `get()` as a plain string argument.

### INPUTS header convention for Frame-linked slots

Replace `<link_slot>`, `<target_type>`, `<remote_slot>`, `<threshold_slot>` with your
domain's actual slot names.

```yaml
##
# INPUTS  (slots read)
#   besoin_X           : targeting slot (your sandbox's targeting slot name)
#   <link_slot>        : Frame ref — <target_type> this frame is linked to
#                        (resolved from <link_slot>_ref by Feed.pm at load time)
#   <link_slot>.<remote_slot> : <type> — <description> (read via inter-frame link)
#   _ISA → <spec_type> prototype (injected by Feed.pm via fselect)
#     <threshold_slot>_A / _B / _C : normative thresholds (inherited via _ISA)
##
```

> **Example** (ADA sandbox):
> ```yaml
> #   besoin_wall        : targeting slot
> #   supports           : Frame ref — external_wall this wall buttresses
> #                        (resolved from supports_ref by Feed.pm)
> #   supports.height_m  : float — height of supported wall (via link)
> #   _ISA → masonry_spec prototype
> #     min_str_A / min_str_B / min_str_C : Table 6 thresholds (via _ISA)
> ```

### Checklist — Inter-Frame YAML

- [ ] **Guard on every `get('link')` call** — Option A (fallback) or Option B (hard skip) — see § Navigating a slot→Frame link above
- [ ] `$_->{link_slot}` in `filtre` is the **Frame object** — use `$_->get('link_slot')` there
      if you need to inspect the linked frame inside a `filtre` expression
- [ ] **Never use `$_->{slot}` direct access in `filtre` for inherited slots** —
      `$_->{slot}` only sees direct slots; use `$_->get('slot')` to traverse `_ISA`
- [ ] `$w->get("slot_$dynamic")` — dynamic slot names work, document the possible values
- [ ] INPUTS header: document linked Frame slots as `link.slot_name : type — meaning`

---

## Complete YAML Guide

> **Language rule:** use English keywords by default (`RULE`, `FIND`, `ACTION`, `PREMISES`).
> Switch to French keywords (`REGLE`, `CHERCHER`, `EFFET`, `PREMISSES`) only when the corpus
> processed by `chorus-feed` is in French.
> Sub-keys `attribut` and `filtre` are invariant — no English alias exists in the engine.

### Rule Structure

```yaml
RULE: rule-name                  # mandatory — becomes _ID (deduplication)
TERMINAL: solved                 # optional — 'solved' or 'failed'
PREMISES:                        # optional — metadata for reorder()
  - slot-prerequisite
  - another-slot
FIND:                            # mandatory — defines _SCOPE
  var1:
    attribut: slot-name          # → fmatch(slot => 'slot-name')
    filtre: '$_->prop > 0'       # optional → grep { ... }
  var2:
    attribut: another-slot
CONDITION: '$var1->ok'           # optional — return unless CONDITION
EXCEPTION: 'defined $var1->{r}' # optional — return if EXCEPTION
ACTION: |                        # mandatory — body of _APPLY
  $var1->set('result', $var2->value);
  1
```

> French equivalent (corpus in French): `REGLE` / `CHERCHER` / `EFFET` / `PREMISSES`

### FIND — Variable Scope

```yaml
FIND:
  p:
    attribut: classe_bois
# → _SCOPE => { p => sub { [ fmatch(slot => 'classe_bois') ] } }

  p:
    attribut: level
    filtre: '$_->level < 5'
# → _SCOPE => { p => sub { [ grep { $_->level < 5 } fmatch(slot => 'level') ] } }
```

- **`attribut`**: slot passed to `fmatch` — defines the search space.
- **`filtre`**: Perl expression on **`$_`** (the iterated Frame) — narrows the space **before** the combinatorial loop → critical optimization.

> ⛔ **`$f` is not defined inside `filtre`** — `$f` (or any scope variable) only exists inside `ACTION`/`EFFET`, after `my $f = $opts{f}` is executed by `_APPLY`. Using `$f->` in a `filtre` expression causes `Global symbol "$f" requires explicit package name` at rule compilation time.
> ```yaml
> # ⛔ WRONG — $f not in scope here
> FIND:
>   f:
>     attribut: type_element
>     filtre: "defined $f->{type_element} && defined $f->{classe_bois}"
>
> # ✅ CORRECT — use $_ (the iterated Frame)
> FIND:
>   f:
>     attribut: type_element
>     filtre: "defined $_->{type_element} && defined $_->{classe_bois}"
> ```
> Multi-line block scalars (`|`) follow the same rule — every line uses `$_`:
> ```yaml
>     filtre: |
>       defined $_->{type_element}
>       && defined $_->{classe_bois}
> ```

### CONDITION vs EXCEPTION

| Key | Semantics | Generated code |
|---|---|---|
| `CONDITION` | rule **must** be true to fire | `return unless <CONDITION>;` |
| `EXCEPTION` | rule **must not** fire if true | `return if <EXCEPTION>;` |

> **Idempotence:** always add `EXCEPTION: defined $var->{slot_pose}` to prevent re-firing on the same Frame.

### ACTION — Syntaxes

```yaml
# Single instruction
ACTION: "$frame->increase; 1"

# Multi-line (use | not >)
ACTION: |
  my $W = $p->{width} * $p->{height} ** 2 / 6;
  $p->set('sigma_m', $M / $W);
  1

# Sequential list
ACTION:
  - '$p->set("step1", "y")'
  - '$p->set("done", "y"); 1'
```

> ⚠️ Last instruction must return a truthy value. Use `|` (newlines preserved), never `>`.

### TERMINAL — Automatic Termination

```yaml
RULE: all-processed
FIND:
  p:
    attribut: status
TERMINAL: solved
EXCEPTION: '$p->{status} ne "FINAL"'
ACTION: "1"
```

- `TERMINAL: solved` — fires when the rule matches and `_APPLY` returns true → reliable, idiomatic.
- `$SELF->solved()` in ACTION — also valid: `$SELF` inside a YAML ACTION is the agent (Engine), so `$SELF->solved()` correctly sets `BOARD->{SOLVED}`. Can be combined with `TERMINAL: solved` or used alone.
- ⛔ **Never** use a global `fmatch` in a YAML `FIND`/`CHERCHER` block for a termination rule → guaranteed infinite loop. Use `fmatch` in `EXCEPTION`/`CONDITION` only (safe — not bound).

### Loading Order

`loadRules($dir)` loads `*.yml` files in **alphabetical order** → name files `R01-`, `R02-`, etc.

Multiple directories = multiple `loadRules()` calls.

### PREMISES — for reorder()

```perl
sub sort_by_interest {
    my ($r1, $r2) = @_;
    return 1  if $r1->_PREMISSES->{CAT_NOM};
    return -1 if $r2->_PREMISSES->{CAT_NOM};
    return 0;
}
$agent->reorder(\&sort_by_interest);
```

---

## Rule Documentation Standard

> **Mandatory for every generated YAML rule.**
> The header language must match the corpus language:
> English header for an English corpus, French header for a French corpus.
> Adapt the field labels accordingly (see both templates below).

### Header template — English corpus

```yaml
##
# RULE: <R0N-rule-slug>
# AGENT: <Namespace>::Agent::<Name>  (pos. N / total)
# CORPUS: §<N> — <standard/document> — <section title>
#
# PURPOSE
#   <One or two sentences describing what this rule checks and why.>
#   <Mention element types in scope if the rule is type-restricted.>
#
# INPUTS  (slots read)
#   <targeting_slot>  : targeting slot — set by <feed | previous agent RNN>
#   <slot_a>          : <type and meaning, e.g. "float — measured deflection in mm">
#   <slot_b>          : <allowed values or range>
#
# OUTPUTS (slots written)
#   <result_slot>     : <"OUI"/"NON", "OK"/"KO", or any domain value> — result of this rule
#   <targeting_slot>  : deleted after processing (consumed targeting slot)
#
# HELPERS  (omit section if none)
#   <helper_name>(<args>)  → <return type and meaning>
#
# GUARD — EXCEPTION: defined $<var>->{<slot_set>}
#   Idempotence — prevents re-processing a Frame already handled in a previous cycle.
##
```

### Header template — French corpus

```yaml
##
# REGLE: <R0N-slug-regle>
# AGENT: <Namespace>::Agent::<Nom>  (pos. N / total)
# CORPUS: §<N> — <norme/document> — <titre section>
#
# OBJECTIF
#   <Une ou deux phrases décrivant ce que vérifie cette règle et pourquoi.>
#   <Mentionner les types d'éléments en scope si la règle est restreinte par type.>
#
# ENTRÉES  (slots lus)
#   <slot_ciblage>    : slot de ciblage — posé par <feed | agent précédent RNN>
#   <slot_a>          : <type et signification, ex. "float — flèche mesurée en mm">
#   <slot_b>          : <valeurs admises ou plage>
#
# SORTIES  (slots écrits)
#   <slot_resultat>   : <"OUI"/"NON", "OK"/"KO", ou valeur domaine> — résultat de la règle
#   <slot_ciblage>    : supprimé après traitement (slot de ciblage consommé)
#
# HELPERS  (supprimer la section si aucun)
#   <nom_helper>(<args>)  → <type retour et signification>
#
# GARDE — EXCEPTION: defined $<var>->{<slot_pose>}
#   Idempotence — évite de retraiter un Frame déjà traité lors d'un cycle précédent.
##
```

### Inline comment rules (ACTION / EFFET body)

- **Group** the code into logical blocks with a one-line comment per block.
- **Annotate every early `return`**: explain *why* the Frame is skipped (out-of-scope type, missing data, etc.).
- **Mark slot writes** that produce the targeting slot for the next agent.
- **Reference the corpus** (§N) on the line that encodes a normative threshold.

```yaml
# English example
ACTION: |
  # Read input slots
  my $val  = $p->get('measured_value');
  return 0 unless defined $val;      # slot absent → frame out of scope, skip silently

  # Normative check — §4.2
  my $min = _min_required($p->{element_type});
  return 0 unless defined $min;      # element type not covered by this rule → skip

  # Write result
  if ($val < $min) {
    $p->set('result_ok', 'NON');
    $p->set('rejection_reason', "value $val < min $min (§4.2)");
    return 1;
  }
  $p->set('result_ok', 'OUI');
  return 1;
```

```yaml
# French example
EFFET: |
  # Lecture des slots d'entrée
  my $val  = $p->get('valeur_mesuree');
  return 0 unless defined $val;      # slot absent → frame hors scope, ignoré silencieusement

  # Vérification normative — §4.2
  my $min = _seuil_min($p->{type_element});
  return 0 unless defined $min;      # type non couvert par cette règle → ignoré

  # Écriture du résultat
  if ($val < $min) {
    $p->set('resultat_ok', 'NON');
    $p->set('motif_refus', "valeur $val < min $min (§4.2)");
    return 1;
  }
  $p->set('resultat_ok', 'OUI');
  return 1;
```

> **⚠️ Language rule — inline comments:** all comments inside `ACTION`/`EFFET` blocks must be
> written in the **corpus language** (English for an English corpus, French for a French corpus).
> The two examples above illustrate this rule — the English and French blocks are mutually exclusive
> depending on the corpus language; never mix languages within a single sandbox.
> → See canonical rule in `chorus-engine.md § Canonical Language Rule`.

> **CORPUS line:** when the rule encodes a single standard article, one `CORPUS:` line suffices.
> When the rule combines several articles, list them all:
> ```yaml
> # CORPUS: §4.2 — NF DTU 31.2 — Section minimale montant porteur
> #          §A.2 — NF DTU 31.2 — Annexe A — Tableaux dimensionnels
> ```

---

## Advanced Mechanisms — See also

For advanced patterns using procedural slots (_AFTER, _BEFORE, _NEEDED, _REQUIRE),
prototype selection (fselect), and inheritance modes, see **`chorus-frame-advanced.md`**.

This section covers the most important cases:

- **§ fselect — Prototype Selection** — scoring-based Frame matching for Pattern B (_ISA via prototypes)
- **§ _TERMINAL_SLOTS / complete()** — Frame validation before pipeline execution
- **§ Inheritance Modes N vs Z** — default behavior and implications for _DEFAULT/_NEEDED resolution

---

## fselect — Prototype Selection (Pattern B)

> See also: `chorus-frame-advanced.md § fselect`.

**Use case:** Select the best-matching Frame from a catalog of prototypes based on observed properties.
This implements Minsky's frame-selection mechanism for domain diagnosis.

### Basic syntax

```perl
# Best match (highest score)
my $proto = fselect(wood_class => 'oak', hardness => 'high');

# All candidates ranked by descending score
my @ranked = fselect(wood_class => 'oak', _all => 1);

# Restrict to a prototype and its declared _ALTERNATIVES (frame network)
my $proto = fselect(wood_class => 'oak', _alternatives => $Bird);

# Restrict search space to a subset of Frames
my $proto = fselect(wood_class => 'oak', _from => \@candidates);

# Accept zero-score matches
my @all = fselect(wood_class => 'oak', _all => 1, _min => 0);
```

### Pattern B in Feed.pm — Automatic _ISA injection

When `chorus-feed` builds a project Frame from JSON, it calls `fselect` to find
the best-matching prototype from a static catalog and injects it via `_ISA`:

```perl
# In chorus-check → Feed.pm load_projet()
my $proto = fselect(
    wood_class => $project_frame->{wood_class},
    treatment  => $project_frame->{treatment},
    _from      => \@normatif_catalog
);
$project_frame->set('_ISA', $proto) if $proto;
```

Result: the project Frame inherits all normative thresholds from its matched prototype.

### Scoring rules

For each candidate Frame in the pool:
- **+1 point** for each slot where the Frame provides the slot AND the resolved value matches the observation
- **Score < 1** (no matches): excluded by default (pass `_min => 0` to include)
- **Best candidate** returned by default; use `_all => 1` to get all ranked candidates

### Common pitfall — unreachable prototypes

If all prototypes score 0, the Frame inherits nothing. To debug:

```perl
# Log the scores for all candidates
my @ranked = fselect(wood_class => 'oak', _all => 1, _min => 0);
for my $proto (@ranked) {
    my $score = ...;  # score not directly accessible — check by re-running with test values
    print "Proto " . $proto->get('id') . " scored $score\n";
}
```

---

## _TERMINAL_SLOTS / complete() — Frame Validation

> See also: `chorus-frame-advanced.md § _TERMINAL_SLOTS / complete()`.

**Use case:** Declare which slots must contain actual data (`_VALUE`) for a Frame
to be considered "complete" in the sense of Minsky's frame model.
Used to validate that a project Frame has been sufficiently populated before execution.

### Basic syntax

Declare terminal slots on a prototype:

```perl
my $proto = Chorus::Frame->new(
    _TERMINAL_SLOTS => ['color', 'size', 'weight'],
);
```

Check if an instance is complete:

```perl
my $instance = Chorus::Frame->new(
    _ISA   => $proto,
    color  => 'red',
    size   => 'large',
    weight => '500g',
);

if ($instance->complete) {
    print "Frame is complete\n";
} else {
    print "Frame is incomplete — missing a terminal slot\n";
}
```

### In chorus-check

Before calling `$expert->process()`, validate all project Frames:

```perl
# In run.pl or chorus-check generated code
for my $elem (@$elements) {
    unless ($elem->complete) {
        warn "Element " . $elem->get('id') . " is incomplete\n";
        next;  # skip or die, depending on policy
    }
}
my $ok = $expert->process($input);
```

---

## Inheritance Modes — N vs Z

> See also: `chorus-frame-advanced.md § Inheritance Modes (N vs Z)`.

Chorus supports two modes for resolving `_VALUE`, `_DEFAULT`, and `_NEEDED` across the inheritance tree.
The default is **Mode N**.

### Mode N (Default) — Breadth-first per valuation key

Each key is searched across the **entire inheritance tree** before moving to the next key:

```
1. Look for _VALUE on (Frame, Frame._ISA, Frame._ISA._ISA, ...)
2. If not found, look for _DEFAULT on the same tree
3. If not found, look for _NEEDED on the same tree
4. If still not found, return the Frame itself
```

**Example:**

```perl
Frame A:
  ├─ _VALUE = 'v1'

Frame B (_ISA => A):
  ├─ _DEFAULT = 'v2'

Frame C (_ISA => B):
  (no _VALUE, _DEFAULT, _NEEDED)

C->get('slot') [Mode N]:
  1. search _VALUE: C (no), B (no), A (yes!) → return 'v1'
```

### Mode Z — Full sequence per frame

Each Frame tests the **full sequence** (`_VALUE → _DEFAULT → _NEEDED`) before descending to parents:

```
1. On Frame: _VALUE? _DEFAULT? _NEEDED?
2. If all absent, on Frame._ISA: _VALUE? _DEFAULT? _NEEDED?
3. Continue up the chain
```

**Example (same Frame structure):**

```perl
C->get('slot') [Mode Z]:
  1. on C: _VALUE? (no) _DEFAULT? (no) _NEEDED? (no)
  2. on B: _VALUE? (no) _DEFAULT? (yes!) → return 'v2'
```

Note the difference: **Mode N returns 'v1', Mode Z returns 'v2'** from the same Frame tree.

### Switching modes

```perl
Chorus::Frame::setMode(GET => 'N');   # Mode N (default)
Chorus::Frame::setMode(GET => 'Z');   # Mode Z
Chorus::Frame::setMode('N');          # short form
```

The mode is a **global setting** — affects all Frame `get()` calls in the application.

### When to use Mode Z

**Mode Z** is useful when:
- You have **multi-level prototypes** where each level adds a new _DEFAULT
- You want **shallower defaults** (nearest ancestor) to take precedence
- You're implementing a **DSL** where each Frame layer defines its own defaults

**Default (Mode N)** is suitable for most use cases — it prioritizes finding the _VALUE
across the full tree before falling back to _DEFAULT.

---

## Checklist — Anti-Pitfalls

### ✅ YAML Rules

- [ ] ⛔ **`type_element` — canonical slot name:** the slot identifying the element type is
      **always** named `type_element` in every `FIND`/`CHERCHER` `attribut:` that routes by
      element type. Never `element_type`, `type`, `kind`, or any other variant.
      A mismatch with the project JSON key (`"type_element"`) causes a SOLVED pipeline with
      **all elements unprocessed** — no error, no warning, 0 processed frames.
      This rule applies to every YAML rule in every sandbox and every `chorus-feed` run.
- [ ] **Header present** — every generated rule starts with the structured comment header (§ Rule Documentation Standard). Language matches the corpus (English or French).
- [ ] **CORPUS line traceable** — `CORPUS:` references the exact standard article (§N) that justifies the rule. If the source is unknown → `# CORPUS: TODO — source not identified in corpus`.
- [ ] **Always** end `ACTION` with a truthy value (`1` or truthy expression)
- [ ] **`filtre` in `FIND`: always use `$_`, never `$f`** — `$f` (scope variable) is only defined inside `ACTION`/`EFFET`. Using `$f->` in `filtre` causes a compilation crash (`Global symbol "$f"`). Use `$_->{slot}` or `$_->get('slot')`.
- [ ] **`CONDITION` must test data presence, not conformance** — a CONDITION that tests a business result (e.g. `$f->{result} eq 'OK'` or a Helper call returning a pass/fail value) silently blocks all non-conforming Frames: the rule never fires on them, so no slot is ever set → downstream agents never see those Frames → silent pipeline gap. Always restrict `CONDITION` to testing slot presence (`defined $f->{slot}`), type routing (`$f->{type} eq '...'`), or the existence of prerequisite computed slots. Move the conformance test into `ACTION`/`EFFET`, which sets the `_ok` slot to `'OUI'` or `'NON'`.
      ```yaml
      # ⛔ WRONG — non-conforming Frames silently skipped; slot never set
      CONDITION: |
        SomeHelper->is_valid($f->{val}, SomeHelper->min_required($f->{type}))
      # ✅ CORRECT — always fires when data is present
      CONDITION: "defined $f->{val} && defined $f->{type}"
      # ACTION then computes and sets 'result_ok' to 'OUI' or 'NON'
      ```
- [ ] **Conditional ACTION without `else`**: if the `if` modifies nothing and returns `1` → infinite loop until `_MAX_CYCLES`.
      ```yaml
      # ⛔ WRONG — infinite loop if condition never true
      ACTION: |
        if ($p->{val} > 5) { $p->set('flag', 'KO') }
        1
      # ✅ CORRECT
      ACTION: |
        if ($p->{val} > 5) { $p->set('flag', 'KO'); return 1 }
        0
      ```
      > Invisible on a sandbox (6 frames), critical at real scale (300 frames × 40 rules).
- [ ] **Always** add `EXCEPTION: defined $var->{slot_pose}` for idempotence
- [ ] Use `|` (block scalar) for multi-line `ACTION`, never `>`
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

---

## Quick Reference — YAML DSL Keys

```
RULE        → _ID              (alias: REGLE — French corpus)
TERMINAL    → 'solved' | 'failed'
PREMISES    → [slot, ...]      (alias: PREMISSES — French corpus)
FIND        → _SCOPE (attribut + filtre optional)   (alias: CHERCHER — French corpus)
CONDITION   → return unless ...
EXCEPTION   → return if ...
ACTION      → _APPLY body (must return true)         (alias: EFFET — French corpus)
```
