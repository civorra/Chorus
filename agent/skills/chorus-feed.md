# Skill — chorus-feed

> Trigger: `chorus-feed <sandbox-name> <corpus> [--enrich] [--harvest-aliases <import-report.org>]`
> Agent: `architect`
>
> `<sandbox-name>`: name of the sandbox directory under `$SANDBOXES/`
> `<corpus>`: plain-text file (`.txt`), Markdown file (`.md`), or inline content —
>              **or** a document file requiring preprocessing (PDF, DOCX, XLSX/CSV, XML/HTML).
>              If a document format is provided, the corresponding conversion skill is called automatically.
> `--enrich`: activates Mode B (incremental enrichment) — absent by default
> `--harvest-aliases <import-report.org>`: activates Mode C — reads a validated import report
>              and integrates its confirmed ✅ mappings into the KB `** Aliases` sections.
>              No `<corpus>` argument is needed in this mode.
>
> **Single responsibility: enrich knowledge.**
> This skill never generates infrastructure code (Feed, shell Agent, Expert, run.pl).
> It produces:
>   - KB org-mode files per agent (`agent/chorus/<slug>.org`)
>   - YAML rule files (`rules/<slug>/R<NN>-xxx.yml`)
>   - Business knowledge Perl helpers (`lib/<Namespace>/Agent/<Slug>/Helpers.pm`)
>   - Pipeline index (`agent/chorus/index.org`)
>
> To validate a project based on this knowledge → use `chorus-check`.


## ⛔ Strict sandbox isolation

**Never read any file, KB, YAML, or artifact from a sandbox other than `<sandbox-name>`.**

This applies regardless of context: even if another sandbox appears to contain similar
or related knowledge, it must be completely ignored. Each sandbox is an independent,
self-contained unit. Cross-sandbox reads are forbidden in all modes (A and B).


## 0. Prerequisites

Load: `chorus-engine-yaml.md` — YAML authoring reference (Frame essentials, Engine rule triggering, YAML guide, checklists)

### ⛔ Document Format Guard — Auto-conversion

**Before doing anything else**, check the `<corpus>` argument's file extension
(case-insensitive). `chorus-feed` accepts **only** plain-text (`.txt`), Markdown
(`.md`), or inline content (no file extension). **However**, if a preprocessing-required
format is detected, the corresponding conversion skill is invoked automatically.

| Extension | Format | Auto-conversion skill | Extracted file(s) |
|---|---|---|---|
| `.pdf` | PDF | `chorus-pdf <sandbox-name> <file.pdf> --auto` | `<NNN>-<slug>-text.txt` or `-vision.md` |
| `.docx` | Word | `chorus-word <sandbox-name> <file.docx>` | `<NNN>-<slug>-text.txt` or `-vision.md` |
| `.xlsx` / `.csv` | Spreadsheet | `chorus-excel <sandbox-name> <file>` | `<NNN>-<slug>-text.txt` or `-vision.md` |
| `.xml` / `.html` / `.htm` | XML/HTML | `chorus-xml <sandbox-name> <file>` | `<NNN>-<slug>-content.md` or `-vision.md` |
| `.txt` / `.md` / inline | Plain/Markdown | *(none)* | Use as-is |

**Auto-conversion logic:**

```
If <corpus> ends in .pdf, .docx, .xlsx, .csv, .xml, .html, .htm (case-insensitive):
  1. Invoke the corresponding skill (chorus-pdf, chorus-word, chorus-excel, or chorus-xml)
  2. Wait for completion (exit code 0 expected)
  3. Auto-detect the output file: glob corpus/[0-9][0-9][0-9]-*-{text,content,vision}.{txt,md}
     (newest by mtime if multiple outputs)
  4. Use the extracted file as <corpus> for the remainder of Phase 1+

Else:
  <corpus> is accepted as-is (plain .txt, .md, or inline content)
```

**Example:**

```bash
# Input is a PDF
chorus-feed test-05-RGPD corpus/002-norme-publiee.pdf
→ [auto] Detected .pdf format
→ [auto] Calling: chorus-pdf test-05-RGPD corpus/002-norme-publiee.pdf --auto
→ [auto] Waiting for completion...
→ [auto] Output detected: corpus/003-norme-publiee-vision.md
→ [auto] Using corpus/003-norme-publiee-vision.md as source
→ [feed] Mode A initialization with corpus/003-norme-publiee-vision.md
```

Inline content (no file extension) is always accepted as-is.
After auto-conversion (if any), proceed to Phase 0 — Sandbox Initialization.


## Mode Selection

**Default: Mode A — always, regardless of the sandbox state.**

The `--enrich` flag is required to activate Mode B.

| Condition | Mode |
|---|---|
| No `--enrich` flag | **Mode A** — ignore any existing KB in the sandbox |
| `--enrich` flag present | **Mode B** — read existing KB and enrich |
| `--harvest-aliases <report>` present | **Mode C** — read KB + import report, integrate aliases only |

> ⚠ Without `--enrich`, **never** read `agent/chorus/`, existing YAMLs, or
> any other KB artifact from the sandbox — even if the `<sandbox-name>` directory already exists.
> The provided corpus is treated as a fresh source, independent of any existing context.


## Mode A — Initialization (new corpus, fresh base)

Used when `<sandbox-name>` does not yet exist or does not contain a KB.

### Phase 0 — Sandbox Initialization

Create the directory structure:

```bash
SANDBOX="$SANDBOXES/<sandbox-name>"
mkdir -p "$SANDBOX/agent/chorus"
mkdir -p "$SANDBOX/corpus"
mkdir -p "$SANDBOX/rules"
mkdir -p "$SANDBOX/lib"
```

Save the corpus in `corpus/001-<slug-source>.txt`
(convention: numbered to allow incremental enrichment).

Create `README.org`:

```org
#+TITLE: Sandbox <sandbox-name>
#+DATE: <date>
#+STATUS: draft

* Corpus
  | Num | Fichier                    | Source              | Date       |
  |-----+----------------------------+---------------------+------------|
  | 001 | corpus/001-<slug>.txt      | <origine>           | <date>     |

* Identified pipeline
  (filled in during Phase 1)

* Agent status
  | Agent | KB | YAML | Helpers | Enrichments |
  |-------+----+------+---------+-------------|

* Session notes
```

### Phase 1 — Corpus Analysis

**1.1 Identify specialties**

Read the corpus in full. Group rules by coherent theme.
Each group = one agent. Criteria:
- rules concerning the same types of Frames
- same incoming/outgoing slots
- orderable sequentially without cyclic dependencies

Result: ordered list of agents (slug + intent + pipeline position).

**1.2 Identify domain Frames**

For each persistent concept in the corpus (≥ 2 slots, stable identity) → Frame.
Intermediate calculations remain as slots, not Frames.

> ⛔ **Canonical slot name — `type_element` is mandatory.**
> The slot identifying the element type **must always be named `type_element`** across
> the entire sandbox: in the KB org (Slot dictionary, FIND/CHERCHER attribut),
> in the YAML rules (`attribut: type_element`), and in the project JSON files.
> Never use `element_type`, `type`, `kind`, `element_kind`, or any other variant.
> A name mismatch between YAML (`attribut: element_type`) and JSON (`"type_element": ...`)
> causes all Frames to be silently invisible to every agent →
> 0 elements processed, pipeline SOLVED but all entries unprocessed.

> **⚠️ Language rule — slot names:** all slot names (except `type_element` and internal engine
> slots `_ISA`, `_SELF`, `_ITEMS`, `_CONTAINER`, etc.) must be named in the **corpus language**.
> French corpus → French slot names (`montant_porteur`, `classe_bois`, `besoin_conformite`).
> English corpus → English slot names (`bearing_member`, `wood_class`, `conformance_need`).
> → See canonical rule in `chorus-engine.md § Canonical Language Rule`.

**1.2b Identify inter-frame relationships**

After identifying domain Frames, examine whether any Frame *belongs to* or *depends on*
another Frame for key properties.  Signs of an inter-frame relationship in the corpus:

- A slot on Frame A duplicates a property of Frame B (e.g. `buttressing_wall.height_m`
  = height of the wall it buttresses — that's `external_wall.height_m`).
- A rule would need a cross-product scope (`FIND: var1: ... var2: ...`) to relate
  two Frame types — this always signals a missing structural link.
- Multiple frames of type A share the same normative thresholds that come from a
  static table indexed by `(type, material, group, …)`.

**For each identified relationship, choose a pattern:**

| Relationship type | Pattern | Implementation |
|---|---|---|
| Element A structurally belongs to / is connected to B | **slot→Frame** | `*_ref` field in JSON → resolved in Feed.pm pass 2 |
| Multiple frames share a normative threshold catalog | **`_ISA` prototype** | `_build_*_catalog()` + `fselect` in Feed.pm |

> → Full implementation guide: `chorus-engine-infra.md § 3. Inter-Frame Relationships`

**Notation in KB org files:**

Document inter-frame slots in the Frame's slot dictionary with a `→` marker.
Replace slot names and target types with your domain's actual vocabulary:

```org
** Slots
| slot              | type      | description                                    |
|-------------------+-----------+------------------------------------------------|
| <link_slot>       | Frame ref | → <target_frame_type> (Pattern A structural)   |
| <link_slot_2>     | Frame ref | → <parent_frame_type> (Pattern A structural)   |
| _ISA              | prototype | → <spec_type> prototype (injected by Feed.pm)  |
```

> **Example** (ADA sandbox):
> `supports → external_wall` ; `building → residential_building` ; `_ISA → masonry_spec`

**`*_ref` fields are OPTIONAL — never add them to `%SLOTS_REQUIS`:**

```perl
# ✅ CORRECT — *_ref absent from required slots (optional link)
'buttressing_wall' => [qw(id type_element buttressing_length_m)],
'external_wall'    => [qw(id type_element wall_type thickness_mm height_m length_m)],
```

> ⛔ Adding `supports_ref` or `building_ref` to `%SLOTS_REQUIS` breaks backward
> compatibility — older project files without these fields will die at load time.
> Rules must use the Option A fallback pattern (see `chorus-engine-yaml.md §
> Navigating a slot→Frame link`) to handle both formats.

**`%REF_FIELDS` in Feed.pm — declare INSIDE `load_projet()`, before pass 1:**

```perl
sub load_projet {
    my ($fichier) = @_;
    # ... JSON load + SLOTS_REQUIS validation ...

    my %REF_FIELDS = (       # ← inside load_projet(), not at module level
        supports_ref => 'supports',
        building_ref => 'building',
        # add new links here
    );
    # ... pass 1 / pass 2 — see chorus-engine-infra.md §3.5 for the full skeleton
}
```

**If Pattern B is also needed (`_ISA` prototypes):** add a `_build_*_catalog()` sub
and a `$inject_isa` closure inside `load_projet()`, called in **both** pass 1 and
pass 2 — see `chorus-engine-infra.md §3.2 and §3.5`.

```perl
# Pattern B addition to load_projet():
my @catalog  = _build_spec_catalog();   # BEFORE pass 1
my $inject_isa = sub { ... };           # captures @catalog
# Call $inject_isa->(\%slots) in both passes
```

**1.2c — Control slots for advanced knowledge modeling**

Beyond Pattern A and B, three Frame control slots can sharpen the generated KB when
the corpus clearly signals their need. **Do not add them speculatively** — apply only
when a corpus pattern explicitly motivates each one.

**`_DEFAULT` — shared fallback on prototypes**

When a Pattern B prototype carries a `_DEFAULT` hash, `get()` returns the fallback
automatically if the domain Frame and its `_ISA` parent both lack the targeted slot.
Use this for normative "applies unless otherwise specified" defaults.

```perl
# In _build_spec_catalog() — prototype with a default bending resistance
Chorus::Frame->new(
    classe_bois  => 'C24',
    fm_k         => 24,         # direct value on the prototype
    _DEFAULT     => { fm_k => 0 },  # fallback if a lookup on a derived class misses
);
```

> **When to use:** corpus phrases such as "default value X unless drawings specify
> otherwise", "applies if not explicitly stated".
>
> **Notation in KB org Slot dictionary:**
> ```org
> | fm_k | float | Bending resistance — default: 0 (via _DEFAULT on prototype) |
> ```
>
> **Generation note:** `chorus-check` adds `_DEFAULT` to the prototype Frame literal
> in `_build_*_catalog()`.  The KB org `Slot dictionary` must document the default
> with a `default:` annotation so `chorus-check` can infer the value.

**`_NEEDED` — backward-chaining lazy derivation**

`_NEEDED` is a coderef stored on a Frame.  When `get('slot')` finds nothing in the
Frame or its `_ISA` chain, it calls `_NEEDED` as a last resort, enabling on-demand
computation of derived slots.

```perl
# In Feed.pm — after Frame creation, inside load_projet()
$frame->set('_NEEDED', sub {
    my ($slot) = @_;
    return unless $slot eq 'epaisseur_totale_mm';   # handle only this slot
    my @couches = @{ $SELF->get('couches') // [] };
    return unless @couches;
    my $total = 0;
    $total += ($_->get('epaisseur_mm') // 0) for @couches;
    $SELF->set('epaisseur_totale_mm', $total);   # cache via set → visible to fmatch
    return $total;
});
```

> **When to use:** when the corpus defines a slot as derivable from others (formulas
> such as "= sum of", "= product of", "calculated from") and not all project files
> will supply it explicitly.
>
> ⚠️ **`_NEEDED` is NOT automatically cached** — every `get()` re-evaluates the coderef.
> The explicit `$SELF->set(...)` in the example above IS the cache mechanism: once the
> slot is written via `set()`, subsequent `get()` calls find `_VALUE` and skip `_NEEDED`.
> Without that `set()` call, each `get()` recomputes from scratch (costly + not visible to `fmatch`).
>
> **Corpus signals:** explicit derivation formulas; slots present in some project
> files but absent in others (optional but computable).
>
> **Notation in KB org Slot dictionary:**
> ```org
> | epaisseur_totale_mm | float | Derived via _NEEDED from couches[].epaisseur_mm |
> ```
>
> **Generation note:** `chorus-feed` annotates the slot with `Derived:` in the KB org.
> `chorus-check` generates the `_NEEDED` coderef in `load_projet()` immediately after
> Frame creation.  The derivation formula comes from the KB org annotation.

**`_AFTER` — forward propagation (strict guardrails required)**

`_AFTER` is a coderef called **after** `set()` modifies a slot.  It can propagate a
change to other Frames.  Use only when the corpus explicitly states a dependency
between Frame types ("when X changes, Y must be re-evaluated").

```perl
# In Feed.pm — after Frame creation, inside load_projet()
# ⚠️ Always capture $SELF BEFORE any set() call on another Frame
$frame->set('_AFTER', sub {
    my ($slot, $new_val) = @_;
    return unless $slot eq 'classe_conductivite';   # react only to this slot
    my $ctx = $SELF;                                # capture BEFORE any set()
    for my $dep (fmatch(slot => 'materiau_ref')) {
        next unless ($dep->get('materiau_ref') // '') == $ctx;
        $dep->set('besoin_thermique', 1);           # targeting slot for next agent
    }
});
```

> ⛔ **`_AFTER` is last resort — use only when ALL of the following hold:**
> 1. The corpus explicitly states a dependency between two Frame types.
> 2. The propagated slot is a **targeting slot** — never a result slot (would bypass
>    idempotence guards and trigger re-processing).
> 3. The closure never calls `set()` on the Frame that owns it (circular propagation).
> 4. `$SELF` is captured at the very top of the closure — before any `set()`.
>
> **Prefer** agent ordering in the pipeline or a targeting-slot rule in `FIND` —
> these cover the vast majority of cases without `_AFTER` complexity.
>
> **Notation in KB org Slot dictionary:**
> ```org
> | classe_conductivite | enum | Triggers besoin_thermique on dependent frames (_AFTER) |
> ```

**`_BEFORE` — Pre-write normalization hook**

`_BEFORE` is a coderef called **before** a slot value is written (before validation).
Use for normalizing or sanitizing input values.

```perl
# In Feed.pm — after Frame creation
$frame->set('_BEFORE', sub {
    my ($slot, $new_val) = @_;
    return $new_val unless $slot eq 'classe_bois';   # only normalize this slot
    # Normalize case
    return uc($new_val);  # return normalized value
});
```

> **When to use:** the corpus defines data that arrives in inconsistent formats
> (e.g., "Oak" vs "oak" vs "OAK") and normalization is idempotent.
>
> **Notation in KB org:** rarely needed — defaults to none unless corpus explicitly
> shows normalization rules.

**`_REQUIRE` — Validation hook (blocks write)**

`_REQUIRE` is a coderef called to validate a new value **before** storage.
Return the constant `REQUIRE_FAILED` (value: `-1`) to **abort** the write.

```perl
# In Feed.pm — after Frame creation
$frame->set('_REQUIRE', sub {
    my ($new_val) = @_;
    return -1 if (defined $new_val) and $new_val < 0;  # reject negative
    return 1;  # allow write
});
```

> **When to use:** the corpus defines domain constraints (minimum/maximum, non-empty,
> enum values) that **must never** be violated.
>
> **Notation in KB org:** rarely needed — defaults to none unless corpus explicitly
> states hard constraints (e.g., "must be positive", "must be one of: A, B, C").
>
> **See also:** `chorus-frame-advanced.md § Procedural Slots — $SELF Capture Rules`
> for full details on $SELF capture and inheritance interactions.

**Hooks lifecycle order** — when `$frame->set('slot', $val)` is called:

```
_REQUIRE($slot, $val)  → return -1 to abort write, anything else to allow
_BEFORE($slot, $val)   → return normalized value to store
[slot written to _VALUE + %REPOSITORY updated]
_AFTER($slot, $val)    → forward propagation to other Frames
```

> If `_REQUIRE` returns `-1`, neither `_BEFORE` nor `_AFTER` fires.
> `_BEFORE` fires before validation is complete — return the (possibly modified) value,
> not a boolean.

---

> ### ⚠️ Automation scope — what is and is not automatic
>
> **Re-creating a sandbox from the same corpus does NOT automatically reproduce
> inter-frame relationships.** Here is what each tool does:
>
> | Step | Tool | Automatic? | Condition |
> |---|---|---|---|
> | Detect relationships in corpus | `chorus-feed` | ✅ **yes** — if corpus signals are clear (§1.2b) | AI judgment required |
> | Annotate KB org with `→` markers | `chorus-feed` | ✅ **yes** — follows §1.2b guidance | Depends on detection |
> | Generate YAML rules with `$w->get('link')` | `chorus-feed` | ✅ **yes** — if KB annotated | Option A fallback pattern |
> | Generate Feed.pm 2-pass + `%REF_FIELDS` | `chorus-check` | ✅ **yes** — if KB has `→` annotations | Depends on KB quality |
> | Generate `_build_*_catalog()` + `$inject_isa` | `chorus-check` | 🟡 **partial** — catalog values from corpus | Normative thresholds required |
> | Add `*_ref` fields to JSON project files | **manual** | ❌ **never automatic** | See below |
> | Detect `_DEFAULT` need in corpus | `chorus-feed` | 🟡 **yes** — if corpus says "default X unless" | KB org `Slot dictionary` `default:` annotation required |
> | Generate `_DEFAULT` on prototypes | `chorus-check` | 🟡 **partial** — reads `default:` from KB org | `chorus-feed` must annotate the slot first |
> | Detect `_NEEDED` derivation in corpus | `chorus-feed` | 🟡 **yes** — if corpus has explicit formula | KB org `Slot dictionary` `Derived:` annotation required |
> | Generate `_NEEDED` coderef in Feed.pm | `chorus-check` | 🟡 **partial** — reads `Derived:` from KB org | Formula must be fully specified in KB org |
> | Detect `_AFTER` dependency in corpus | `chorus-feed` | 🟡 **yes** — only if dependency is explicit | KB org notation: `Triggers X on Y (_AFTER)` |
> | Generate `_AFTER` hook in Feed.pm | **manual** | ❌ **never automatic** | Too risky to generate; engineer validates guardrails |
>
> **Why `*_ref` fields in JSON are always manual:**
>
> `*_ref` fields encode **project structure** — which actual wall element belongs to which
> actual building, which buttressing wall supports which external wall.  This information
> comes from the **project document** (drawings, BIM, specs), not from the normative
> corpus.  `chorus-feed` and `chorus-check` work on the corpus; they cannot know which
> specific project element is linked to which other.
>
> `chorus-import-project` (when aligning a real project document to the KB) is the
> right tool to populate these fields — provided the project document contains explicit
> element relationships.  Otherwise, the engineer or project analyst fills them manually.

---

**1.3 Identify the pipeline**

Order agents by data dependency:
agent N sets slot X → agent N+1 consumes X → N+1 after N.

**1.4 Extract XREF INDEX (hybrid corpus only)**

If the corpus file is a `-vision.md` produced by `chorus-pdf --hybrid`, it may contain
a `=== XREF INDEX ===` block at the end of the file. This block lists identifiers found
in figures (callout tags, part numbers, element codes) together with their text
occurrences — it is a ready-made synonym/alias map between figure labels and corpus
terms.

**Detection:**

```python
import re

with open(corpus_path, encoding="utf-8") as f:
    corpus_text = f.read()

xref_block_match = re.search(
    r'=== XREF INDEX ===(.*?)=== END XREF INDEX ===',
    corpus_text, re.DOTALL
)
xref_entries = {}   # {identifier: [snippet, ...]}
if xref_block_match:
    block = xref_block_match.group(1)
    current_id = None
    for line in block.splitlines():
        m_id  = re.match(r'^## (.+)$', line.strip())
        m_occ = re.match(r'^\s*Text occurrence \(p\.\d+\):\s*(.+)$', line)
        if m_id:
            current_id = m_id.group(1).strip()
            xref_entries[current_id] = []
        elif m_occ and current_id:
            xref_entries[current_id].append(m_occ.group(1).strip())
```

**Integration into the KB Ontology:**

For each `(identifier, snippets)` pair in `xref_entries`:

1. Search the corpus text and the already-identified Frame types / slot names for a
   term that co-occurs with `identifier` in the snippets (within ≤ 2 sentences).
2. If a confident match is found (same element clearly named by both `identifier`
   and a corpus term):
   - Add an alias entry in the `Ontologie` section of the relevant `<slug>.org`:
     ```org
     ** Aliases from figures
        | Figure label | Corpus term / slot              | Source                  |
        |--------------+---------------------------------+-------------------------|
        | M-001        | montant_porteur                 | xref: Figure 3, p.12    |
        | Z-A2         | lisse_haute                     | xref: Figure 3, p.12    |
     ```
   - If the label maps to a `type_element` value → add it to the `Catalogue des Frames`
     under the matching Frame as an `# alias:` comment:
     ```org
     *** montant_porteur
         # alias: M-001 (figure label — corpus p.12)
         Slots d'entrée  : type_element
         Slots calculés  : ...
     ```
3. If the match is uncertain (identifier appears in snippets alongside multiple
   candidate terms):
   - Add the entry with a `# TODO: ambiguous alias` comment — do not map silently.
4. If no corpus term co-occurs with the identifier in the snippets:
   - Omit from the Ontology — do not invent a mapping.

> ⚠️ **This phase adds zero API calls.** The XREF INDEX was produced at no extra cost
> by `chorus-pdf --hybrid`. Reading it is a text-only pass on the already-loaded corpus.
>
> **Scope:** only `-vision.md` corpus files contain a XREF INDEX. `.txt` (text mode)
> and `--auto`/`--images` outputs do not — skip this phase silently if the block is absent.

#### Frame catalog format — mandatory slot classification

Every Frame entry in the `Catalogue des Frames` section of a `<slug>.org` **must** use
the three-line slot classification below. **Never use `Slots obligatoires` alone** —
it conflates input and output slots, which causes `chorus-check` to generate a `Feed.pm`
that rejects projects built by `chorus-create-project` (those provide only `type_element`).

```org
** <frame_name>
   Slots d'entrée  : type_element[, <slot_b_if_project_data>]
   Slots calculés  : <slot_x>, <slot_y>, <slot_z>   ← written by YAML rules
   Slots optionnels: <slot_opt_a>, <slot_opt_b>

   *** type_element = <value>
       ...
```

**Classification rules:**

| Category | Definition | Goes into `%SLOTS_REQUIS` ? |
|---|---|---|
| `Slots d'entrée` | Slots that **must** come from the project JSON. Always includes `type_element`. Include additional slots only if no YAML rule can compute them from `type_element` alone (e.g. a project measurement like `height_m`). | ✅ yes |
| `Slots calculés` | Slots written by YAML `ACTION`/`EFFET` blocks. Never required at load time. | ❌ no |
| `Slots optionnels` | Slots that may or may not be present; rules handle their absence gracefully. | ❌ no |

> **`Slots d'entrée` for rule-only sandboxes:** in a sandbox where every non-`type_element`
> slot is computed by rules, `Slots d'entrée` is always just `type_element`.
> Cross-test projects (e.g. `projet-cross.json`) may pre-populate computed slots to test
> guard interactions — `Feed.pm` accepts this because it validates only `Slots d'entrée`.

> **Backward compatibility:** existing org files that still use `Slots obligatoires`
> will cause `chorus-check` to fall back to the legacy behaviour (all listed slots
> validated at load time). Migrate them manually by splitting into `Slots d'entrée` +
> `Slots calculés` (see Python migration script pattern used on `scope-eu.org` and
> `test-02`/`test-04` sandboxes). `chorus-feed --enrich` does **not** perform this
> migration — it only adds new corpus-derived content.

---

### Phase 2 — Targeting Strategy (_SCOPE)

**Do not skip this phase.**

**2.1 Reminder**

`_SCOPE` → Cartesian product. `fmatch(slot => 'X')` returns all Frames
carrying X. The `filtre` reduces **before** the combinatorial loop.
A Frame is invisible to an agent if it does not carry the targeted slot.

**2.2 Rule A vs B**

```
Volume Frames < 50  AND  discriminating slots well distributed → Strategy A
Otherwise                                                       → Strategy B
```
When in doubt → prefer B (always more efficient).

> ⚠️ **Scalability — volume rule:** if the expected number of Frames exceeds 100,
> **always force Strategy B** (presence slot + `EXCEPTION` on each rule).
> Strategy A without `filtre` on a scope of > 100 Frames risks O(N²)
> as soon as `FIND` has multiple variables (unreduced Cartesian product).

**2.3 `_MAX_CYCLES` sizing**

Document in the `Constraints & Pitfalls` section of each agent KB:

```
_MAX_CYCLES recommended: N_frames × N_rules_agent × N_agents × 10
```

Example for a real construction pipeline (300 elements, 5 agents, 8 rules/agent):

```perl
_MAX_CYCLES => 300 * 8 * 5 * 10,   # = 120 000
```

The engine's default value (`10 000`) is a safeguard against infinite loops
— it must be calibrated to the expected volume, not used as-is.

**2.3 Strategy B — presence slot**
- Name: `besoin_<slug_underscore>` (convention)
- Set by: initial feed (agent 1) or agent N-1 in its ACTION (subsequent agents)

**2.4 Strategy A — discriminating slot**
- Identify the common slot + filter value
- If `fmatch` returns > 100 Frames before `grep` → reconsider B

### Phase 3 — Fill the KB per agent

> **⚠️ Language rule — KB org files:** all free text in `<slug>.org` (section headings,
> slot descriptions, rule comments, domain notes, ontology labels, pitfall descriptions)
> must be written in the **corpus language**.
> → See canonical rule in `chorus-engine.md § Canonical Language Rule`.

Create `$SANDBOX/agent/chorus/<slug>.org` from `_template.org`.
Mandatory fill order:

1. Header (`#+AGENT`, `#+PIPELINE_POS`, `#+RULES_DIR`)
2. Domain
3. **Targeting slots** — strategy + table + pre-population contract
4. Pipeline I/O (incoming / outgoing slots)
5. Ontology — including `** Aliases` section (see below)
6. Frame catalog — see **§ Frame catalog format** above (**`Slots d'entrée` / `Slots calculés` / `Slots optionnels`**)
7. Slot dictionary
8. Rule catalog
9. **Perl Helpers** — signatures + complete business logic code
10. Constraints & Pitfalls

#### Ontology — mandatory `** Aliases` section

Every `<slug>.org` file **must include** a `** Aliases` section inside the `* Ontologie`
heading. This section is the canonical synonym/alias table for `chorus-import-project`
Phase 3 terminology alignment.

**Structure:**

```org
** Aliases
   Sources: corpus §<N> definitions, normative lexicons, XREF INDEX (hybrid corpus)
   | Canonical KB form (slot / type_element value) | Project-side variants                              | Source                        |
   |------------------------------------------------|----------------------------------------------------|-------------------------------|
   | montant_porteur                                | poteau porteur, poteau de rive, stud porteur       | corpus §2.1 — Definitions     |
   | classe_bois "C24"                              | C 24, C24 EN338, classe résistance C24             | NF EN 338 §4 table 1          |
   | entraxe_mm                                     | pas, inter-axe, espacement entre montants          | corpus §3.4                   |
   | epaisseur_mm                                   | e=, ep=, épaisseur totale, ep. isolant             | corpus §5.1                   |
```

**Population rules:**

1. **From corpus definitions/lexicons:** scan the corpus for sections titled
   "Definitions", "Terminology", "Glossary", "Lexique", "Définitions", or equivalent.
   Each defined term → alias entry in the table.

2. **From XREF INDEX (hybrid corpus only):** if a `=== XREF INDEX ===` block was
   processed in Phase 1.4, the confirmed `(identifier → corpus term)` mappings are
   added here with source `xref: Figure N, p.N`.

3. **From cross-references within the corpus:** when the corpus uses multiple names
   for the same concept (e.g. "montant porteur" and "poteau porteur" used interchangeably
   in different sections), record both as aliases of the canonical KB form.

4. **Unknown variants — leave the table sparse rather than invent:** if the corpus
   provides no synonyms for a term, the aliases column is empty. Never fabricate aliases
   from general knowledge — only record what the corpus explicitly supports.

> ⚠️ **Empty is valid.** A sandbox whose corpus contains no definition section will have
> a `** Aliases` table with zero rows. The table header must still be present — its absence
> is an error. An empty table is a clear signal that `--harvest-aliases` imports will
> contribute the bulk of real-world terminology.

**Aliases from figures — sub-section (hybrid corpus only):**

When Phase 1.4 produced confirmed `(figure label → type_element)` mappings, add a
dedicated sub-section:

```org
*** Aliases from figures
    | Figure label | Corpus term / type_element value | Source                 |
    |--------------+----------------------------------+------------------------|
    | M-001        | montant_porteur                  | xref: Figure 3, p.12   |
    | Z-A2         | lisse_haute                      | xref: Figure 3, p.12   |
```

This sub-section is read first by Phase 3 of `chorus-import-project` (highest confidence).

> **Helpers rule:** a helper belongs to `chorus-feed` (and therefore to the KB)
> if it encodes **knowledge extracted from the corpus**: value tables,
> normalized calculations, regulatory thresholds. It does NOT belong to `chorus-feed`
> if it relates to infrastructure (file access, parsing, networking).

> ⚠️ **Normative tables — externalize into Helpers, not inline in YAMLs.**
> For domains with dense corpora (standards, DTU, EC5, NF EN…), normative
> values (resistances, exposure classes, regulatory thresholds…) must
> be centralized in `Helpers.pm` rather than coded as scalars in YAML `ACTION`s.
> Advantages: updates during a normative revision without touching the YAMLs;
> traceability to the source (comment `Source corpus: §<N> — <title>`);
> unit tests independent of the rules.
>
> **Traceability rule:** each threshold or normative table in `Helpers.pm`
> must be annotated with its corpus source:
> ```perl
> # Source corpus: §5.3 tab. 1 — NF EN 338:2016 — Bending resistance by class
> my %FM_PAR_CLASSE = (C14 => 14, C16 => 16, C18 => 18, C24 => 24, C30 => 30);
> ```
> If the source is not identifiable → document the uncertainty in a `# TODO` comment.

Points to watch:
- Idempotence: `EXCEPTION` on every rule that sets a slot — **two patterns depending on semantics**:
  - **Pattern 1 — "first writer wins"** (default, classification rules):
    `EXCEPTION: defined $var->{<slot_pose>}`
    Use when only one rule among siblings should fire. Once any rule writes the slot, all are blocked.
  - **Pattern 2 — "veto / override"** (exclusion, priority, short-circuit):
    `EXCEPTION: '($var->{<slot_pose>} // "") eq "<veto_value>"'`
    Use when the rule must be able to **overwrite** a value already set by a sibling rule.
    Idempotence is still guaranteed: the rule stops once it has written `<veto_value>`.
    ⚠️ A veto rule with Pattern 1 (`defined`) will be **permanently blocked** if any sibling fires
    first — the exclusion is silently never applied, even though the engine replays all rules.
  The guard slot **must be one of the slots written by that rule's ACTION** (`$f->set('X', ...)`).
  → `Chorus::Engine::loadRules()` emits a `warn` automatically if the guard slot is not written
  by the rule — immediate feedback at every `perl run.pl`, not deferred to `chorus-check`.
- Termination: document in which rule and under what condition `solved()` is called
- Naming: `R<NN>-<slug>.yml` — alphabetical order = **load order only**.
  ⚠️ **Load order ≠ firing order.** The engine retries all rules every cycle. R03 can fire
  before R01 within the same agent's inference, and equally, R01 can fire *after* R02 in a
  later cycle (e.g. if R01 depends on a slot written by R02). Rule numbers reflect
  load order only — **dependency direction is independent of rule numbering**.
  Never design a rule that silently assumes a lower-numbered rule has already fired in the
  current cycle, and never assume a higher-numbered rule fires last.
  Cross-rule slot dependencies must be guarded explicitly — see checklist item below.

### Phase 4 — Create `agent/chorus/index.org`

```org
#+TITLE: Pipeline — <sandbox-name>

* Pipeline global
  | Pos | Agent (module Perl)     | Slug    | KB                 | Statut |
  |-----+-------------------------+---------+--------------------+--------|
  |   1 | <Namespace>::Agent::Xxx | <slug>  | agent/chorus/x.org   | draft  |

* Pipeline consistency
  - Agent 1 targeting slot: set by → initial feed
  - Agent 2 targeting slot: set by → agent 1 (R<NN>-xxx.yml, ACTION)
  - Termination agent: <Name> pos <N> → rule <Rxx> → solved()

* Integrated corpus
  | Num | Fichier              | Agents affected     |
  |-----+----------------------+---------------------|
  | 001 | corpus/001-xxx.txt   | all (initialization)|
```

### Phase 5 — Generate YAML files

> **Language rule:** use English keywords by default (`RULE`, `FIND`, `ACTION`, `PREMISES`).
> Use French keywords (`REGLE`, `CHERCHER`, `EFFET`, `PREMISSES`) only when the corpus is in French.
> **Header language must match the corpus language** — see `chorus-engine-yaml.md § Rule Documentation Standard`.

> **Documentation rule — mandatory for every generated rule:**
> Each `.yml` file must open with the structured header defined in
> `chorus-engine-yaml.md § Rule Documentation Standard`.
> Fill in: `RULE`/`REGLE`, `AGENT` (module + pipeline position), `CORPUS` (§N reference),
> `PURPOSE`/`OBJECTIF`, `INPUTS`/`ENTRÉES`, `OUTPUTS`/`SORTIES`, `HELPERS` (if any), `GUARD`.
> The `ACTION`/`EFFET` body must include inline comments per logical block
> (see inline comment rules in `chorus-engine-yaml.md § Rule Documentation Standard`).
> A rule without its header is **incomplete** — treat it as a generation defect.

For each rule in the `Rule catalog` of each KB:

```yaml
##
# RULE: <R0N-rule-slug>                          ← or REGLE: for French corpus
# AGENT: <Namespace>::Agent::<Name>  (pos. N / total)
# CORPUS: §<N> — <standard> — <section title>
#
# PURPOSE
#   <What this rule checks and why. Mention restricted element types if applicable.>
#
# INPUTS  (slots read)
#   <targeting_slot>  : targeting slot — set by <feed | previous agent RNN>
#   <slot_a>          : <type and meaning>
#
# OUTPUTS (slots written)
#   <result_slot>     : <domain values> — result of this rule
#
# HELPERS  (omit if none)
#   <helper_name>(<args>)  → <return type>
#
# GUARD — EXCEPTION: defined $<var>->{<slot_set>}
#   Pattern 1 — "first writer wins": use for classification rules (only one sibling fires).
#   Pattern 2 — "veto/override": use EXCEPTION: '($<var>->{<slot_set>} // "") eq "<veto_value>"'
#   when this rule must override a value already written by a sibling in a previous cycle.
#   → chorus-engine-yaml.md § CONDITION vs EXCEPTION
##
RULE: <kebab-case-name>          # mandatory — becomes _ID (deduplication)
TERMINAL: solved                 # optional — 'solved' or 'failed'
                                 # when the rule fires AND TERMINAL is present →
                                 # the engine calls solved()/failed() automatically
PREMISES:                        # optional — prerequisite slots for reorder()
  - <slot-prerequisite>          # used by $agent->reorder(\&fn) to sort
  - <another-slot>               # rules by relevance dynamically
FIND:                            # mandatory — defines _SCOPE
  <var>:
    attribut: <targeting-slot>
    filtre: '<expression for strategy A>'
EXCEPTION: defined $<var>->{<slot_set>}    # idempotence — return if
CONDITION: '<optional-guard>'              # return unless
ACTION: |
  # ⚠️ Flow controls in ACTION: use $SELF (not $agent) → chorus-engine §1.3
  # <Logical block comment>
  <Perl code with inline comments per block>
  1
```

**When to use `TERMINAL` vs `$SELF->solved()` in ACTION:**
- `TERMINAL: solved` — the rule fires and that alone is sufficient to terminate.
  ⚠️ **Multi-patient pipelines:** `TERMINAL: solved` fires immediately after the **first matching
  Frame** is processed. Never place `TERMINAL: solved` on a per-patient computation rule — the
  pipeline would stop after treating only the first patient.
  → For multi-patient pipelines, always use the **two-rule pattern** described below.
- `$SELF->solved()` in ACTION — when the rule must check a condition before concluding.
  ⚠️ `$agent` is **not** available in a YAML ACTION (error `Global symbol "$agent"`) —
  use **exclusively `$SELF`** for flow control in ACTIONs.

> ⚠️ **fmatch in YAML — where it is safe and where it is not:**
>
> | Location | Effect | Verdict |
> |---|---|---|
> | `fmatch` in **ACTION** | Rule fires on every Frame, returns 0 indefinitely → `_MAX_CYCLES` reached | ⛔ infinite loop |
> | `fmatch` in **EXCEPTION** | Rule is simply *skipped* when pending Frames exist; fires only when all done | ✅ safe |
>
> **⛔ ANTIPATTERN — `fmatch` in ACTION → guaranteed infinite loop:**
>
> ```yaml
> RULE: termination
> FIND:
>   p:
>     attribut: needs_check
> ACTION: |
>   my @pending = grep { !defined $_->{status} }
>                 Chorus::Frame::fmatch(slot => 'needs_check');
>   if (@pending == 0) { $SELF->solved(); return 1 }
>   0
> ```
>
> **✅ Preferred pattern — two-rule split (MCP-compatible):**
>
> For the last agent of a multi-patient pipeline, always generate **two rules**:
>
> ```yaml
> # Rule A — per-Frame computation (no TERMINAL)
> RULE: compute-final-result
> FIND:
>   p:
>     attribut: <targeting_slot>
> CONDITION: defined $p->{<prerequisite_slot>}
> EXCEPTION: defined $p->{<result_slot>}
> ACTION: |
>   # ... compute $result ...
>   $p->set('<result_slot>', $result);
>   1
>
> # Rule B — global termination (EXCEPTION fmatch + TERMINAL: solved)
> # Fires only when ALL Frames have <result_slot> set.
> RULE: termination
> TERMINAL: solved
> FIND:
>   dummy:
>     attribut: <targeting_slot>
> EXCEPTION: scalar(grep { !defined $_->{<result_slot>} } Chorus::Frame::fmatch(slot => '<targeting_slot>')) > 0
> ACTION: "1"
> ```
>
> This pattern is loaded by `loadRules()` and is fully MCP-compatible.
> `addrule()` (pure Perl) is a valid fallback but is invisible to MCP mode — prefer the YAML pattern above.
> See `chorus-check.md § Phase 3` for the canonical reference.

**When to document `PREMISES`:**
Always document if the agent is likely to use `reorder()` to
optimize rule order at runtime. PREMISES declare
the slots the rule needs — the sorting code consults them via `$rule->_PREMISSES`.

YAML Checklist:
- [ ] ⛔ **`type_element` canonical name** — see Phase 1.2 ⛔ note; applies equally to YAML `attribut:` field.
- [ ] **Header present** — every `.yml` file opens with the structured `##` header (RULE/REGLE, AGENT, CORPUS, PURPOSE/OBJECTIF, INPUTS/ENTRÉES, OUTPUTS/SORTIES, HELPERS, GUARD). Header language matches the corpus language.
- [ ] **CORPUS line filled** — references the exact §N article from the corpus. If not identifiable → `# CORPUS: TODO — source not identified`.
- [ ] **ACTION/EFFET body commented** — each logical block has a one-line comment; early `return 0` statements explain why the Frame is skipped.
- [ ] Slot names = Slot dictionary from the KB
- [ ] **`CHERCHER`/`FIND` has a named scope variable** — the scope key must be a variable name (`f:`, `e:`, `p:` …), not directly `attribut:`. Without it the engine treats `attribut` itself as the variable name → runtime crash.
      ```yaml
      # ⛔ WRONG — no scope variable; engine crashes at rule compilation
      CHERCHER:
        attribut: type_element
        filtre: "defined $_->{type_element}"
      # ✅ CORRECT
      CHERCHER:
        f:
          attribut: type_element
          filtre: "defined $_->{type_element}"
      ```
- [ ] **`filtre` uses `$_`, not `$f`** — see `chorus-engine-yaml.md` checklist.
- [ ] **`CONDITION` tests data presence, not conformance** — see `chorus-engine-yaml.md` checklist.
- [ ] Every rule that sets a slot has its idempotence `EXCEPTION`:
      - **Pattern 1** (`defined $var->{slot_set}`) for classification rules — "first writer wins".
      - **Pattern 2** (`($var->{slot_set} // "") eq "<veto_value>"`) for veto/exclusion/override rules
        that must fire even if a sibling has already written the slot in a previous cycle.
      The guard slot must be **written by this rule's ACTION** (`$f->set('slot_set', ...)`).
      `Chorus::Engine::loadRules()` warns automatically if mismatched — check STDERR on first run.
      → See `chorus-engine-yaml.md § CONDITION vs EXCEPTION` for the full decision table.
- [ ] `ACTION` ends with `1` or a truthy expression
- [ ] ⛔ **`$f->{slot} = val` in ACTION** → silent pipeline break (`fmatch` returns 0 Frames downstream) — always use `$f->set('slot', val)` → `chorus-engine §5`
- [ ] ⛔ **CONDITION too restrictive on `type_element`** → silently excludes Frames of other types — prefer testing slot presence → `chorus-engine §5`
- [ ] ⛔ **Conditional ACTION without `else`** → returns `1` even when nothing modified → infinite loop at scale — always `return 1` inside the `if`, `0` as fallback → `chorus-engine §5`
- [ ] Use `|` (block scalar) for multi-line `ACTION` — never `>`
- [ ] Files named `R<NN>-<slug>.yml` (alphabetical = **load order only** — not firing order)
- [ ] ⛔ **Cross-rule slot dependency without CONDITION guard** → silent wrong verdict:
      if rule Rxx reads a slot written by another rule in the same agent, it **must** guard
      with `CONDITION: defined $p->{slot_from_other_rule}`. Without this guard, Rxx may fire
      in cycle 1 with `undef`, write a wrong result, and be permanently blocked by its
      EXCEPTION Pattern 1 — even after the other rule fires in a later cycle.
      The engine handles ordering through cycles, not through rule numbers.
      ⚠️ **This applies regardless of rule numbering:** R01 depending on a slot written by
      R03 is equally valid — the CONDITION guard on R01 will hold until R03 fires, whatever
      the cycle. Never assume a lower-numbered rule fires before a higher-numbered one.
- [ ] ⛔ **`fmatch` in YAML ACTION** → guaranteed infinite loop — use the two-rule pattern (Rule A: per-Frame computation, Rule B: EXCEPTION fmatch + TERMINAL: solved + ACTION: "1") or pure Perl `addrule()` as fallback (see `chorus-check.md` Phase 3)
- [ ] ⛔ **`TERMINAL: solved` on a per-Frame computation rule in multi-patient pipelines** → pipeline stops after the first patient — split into Rule A (computation, no TERMINAL) + Rule B (global termination via EXCEPTION fmatch)
- [ ] If `PREMISES` present: consistent with the KB `Slot dictionary`

### Phase 5.5 — Generate Perl Helpers

For each agent whose KB contains a non-empty `Perl Helpers` section,
create `$SANDBOX/lib/<Namespace>/Agent/<Slug>/Helpers.pm`.

**Criteria for including a helper here:**
The code encodes knowledge extracted from the corpus:
- normative value tables (e.g. resistances by class NF EN 338)
- regulatory calculations (e.g. EC5 §6.3 formula)
- threshold or range from a standard article

**What is NOT a knowledge helper** (→ stays in `chorus-check`):
- file parsing, database access, network calls
- orchestration logic (loops over agents, error handling)

> **⚠️ Language rule — Perl comments in `Helpers.pm`:** all comments (inline and block,
> including `Source corpus`, `Signature`, `Called by` lines) must be written in the
> **corpus language**.
> → See canonical rule in `chorus-engine.md § Canonical Language Rule`.

#### Template `Helpers.pm`

```perl
package <Namespace>::Agent::<Slug>::Helpers;

use strict;
use warnings;
use Exporter 'import';

# Exhaustive list of exported helpers — chorus-check imports them all
our @EXPORT_OK = qw(
    <helper1>
    <helper2>
);

# -------------------------------------------------------
# <helper1>
# Source corpus : §<N> — <titre section>
# -------------------------------------------------------
# Signature : <helper1>(<args>) → <type retour>
# Called by: R<NN>-<slug>.yml (ACTION)
sub <helper1> {
    my (<args>) = @_;
    # <corps extrait du corpus>
}

# -------------------------------------------------------
# <helper2>
# Source corpus : §<N> — <titre section>
# -------------------------------------------------------
sub <helper2> {
    my (<args>) = @_;
    # <corps extrait du corpus>
}

1;
```

#### Generation rules

- **One `Helpers.pm` file per agent** — even if there is only one helper.
- **Exhaustive `@EXPORT_OK`** — all helpers listed, none missing.
  `chorus-check` does a full `use ... qw(...)` to make them available
  in the namespace before `loadRules()`.
- **`Source corpus` comment** on each helper — traceability to the standard.
- **⚠️ Org KB parity — mandatory:** after writing `Helpers.pm`, immediately
  update (or write for the first time) the `Perl Helpers` section of
  `agent/chorus/<slug>.org` with the **exact same numeric values and defaults**.
  The org KB is the single source of truth for `chorus-create-project`;
  a divergence here silently corrupts all generated JSON files.
- If a helper is **shared between multiple agents** → place it in
  `lib/<Namespace>/Helpers/Shared.pm` and document it in the KB of
  both agents involved.
- **No side effects** in a helper: no slot writes, no call to
  `$SELF`, no `fmatch`. Helpers compute and return a value —
  the YAML calls `$frame->set()`.
- **Out-of-scope types — defensive fallback:** when a helper is a table lookup
  (section minimums, resistances, thresholds…) and the `type_element` is outside
  the perimeter of the rule (e.g. `chevron` passed to a helper designed for
  `montant_porteur`), always return a neutral value that makes the downstream
  `is_xxx_suffisante` check pass rather than fail:
  ```perl
  sub section_min_requise {
    my (undef, $type, ...) = @_;
    # types outside ossature perimeter → no constraint
    unless ($type =~ /^(montant_porteur|montant_non_porteur|lisse_basse|lisse_haute)$/) {
      return (0, 0);   # (0, 0) → any section satisfies b >= 0 && h >= 0
    }
    ...
  }
  ```
  Returning the maximum sentinel (`(63, 220)`, `9999`…) as fallback causes false
  negatives on out-of-scope elements — they fail a check that was never meant
  for them, producing silently incorrect `NON` verdicts.
  Document out-of-scope handling with a `# types outside perimeter → neutral value` comment.
- **`$SELF` pitfall**: in an `_AFTER` hook or a closure that calls `set()`
  on another Frame, capture `$SELF` **before** any call to `set()`:
  ```perl
  # WRONG — $SELF will be overwritten by the internal set()
  _AFTER => sub { $other->set('x', $SELF->val) }
  # CORRECT
  _AFTER => sub { my $ctx = $SELF; $other->set('x', $ctx->val) }
  ```
  This pitfall concerns helpers called from an `_AFTER` or a procedural slot —
  not pure helpers (compute → return value).

#### Helpers Checklist

- [ ] Every helper referenced in a YAML ACTION has its implementation in `Helpers.pm`
- [ ] `@EXPORT_OK` covers all helpers in the file
- [ ] Every helper has its `Source corpus` comment
- [ ] No side effects (no `set`, no `fmatch`, no I/O)
- [ ] Shared helpers are in `Shared.pm` and documented in both KBs
- [ ] Any helper called from an `_AFTER` or procedural slot: capture `$SELF`
      before any `set()` on another Frame (`my $ctx = $SELF; ...`)
- [ ] **Multi-level slot reads in helper code: use `$frame->get('a b c')`, not `$frame->a->b->c`** —
      the path form preserves `$SELF` as the original frame throughout; the chained form
      silently shifts `$SELF` to each intermediate sub-frame, breaking any `_NEEDED` /
      `_DEFAULT` coderef that reads `$SELF` to reach the domain object.
      → `chorus-frame-advanced.md § get('a b c') vs ->a->b->c`
- [ ] ⚠️ **Org ↔ Helpers.pm parity** — see Phase 5.5 ⚠️ note; generate both from the same source.
- [ ] ⛔ **`_NEEDED` and `_AFTER` coderefs are NOT helpers** — they belong in `load_projet()`
      (generated by `chorus-check`), not in `Helpers.pm`. A `_NEEDED` coderef calls
      `$SELF->set()` (side effect) — this disqualifies it from `Helpers.pm` by definition.
      A slot annotated `Derived:` in the KB org → `_NEEDED` coderef in `load_projet()`.
      A slot annotated `Triggers X on Y (_AFTER)` → `_AFTER` hook in `load_projet()`.

### Phase 6 — Closing

Update `README.org`:
- `Agent status` section: KB ✓, YAML ✓, Helpers ✓ (or `-` if none)
- `Identified pipeline` section: complete table

Invalidate the infrastructure hash so the next `chorus-check` triggers a
full regeneration:

```bash
rm -f $SANDBOX/agent/.kb-hash
rm -f $SANDBOX/.last-check-results.json
```

### Phase 6.5 — Coverage report (mandatory)

**After every Mode A execution**, produce a structured coverage report and
append it to `README.org` under a new `* Coverage` heading.

**Step 1 — Scan the corpus for all normative sections**

Re-read the corpus index (table of contents, section headings, article numbers)
to build an exhaustive list of every normative section / article / table /
diagram present in the corpus.

**Step 2 — Classify each section into one of three buckets**

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

**Step 3 — Write the report to `README.org`**

Append the following block to `README.org`:

```org
* Coverage
  Generated by chorus-feed Mode A — <date>
  Corpus: <corpus-filename>

** ✅ Integrated (<N> rules / tables)
   | Section / Article     | Rules generated          |
   |-----------------------+--------------------------|
   | §<N> — <title>        | R<NN>-<slug>.yml         |
   | Table <N> — <title>   | Helper: <function_name>  |

** ⏭ Deferred — needs chorus-feed --enrich (<N> sections)
   | Section / Article     | Reason          | Suggested new rule / agent       |
   |-----------------------+-----------------+----------------------------------|
   | §<N> — <title>        | <reason>        | <RNN-slug or new-agent>          |

** ⛔ Out of scope (<N> sections)
   | Section / Article     | Reason                                  |
   |-----------------------+-----------------------------------------|
   | §<N> — <title>        | informative / external-norm / procedural|

** Next step
   #+BEGIN_EXAMPLE
   chorus-feed <sandbox-name> <corpus> --enrich
   #+END_EXAMPLE
   → Will process the <N> deferred section(s) listed above.
   Run chorus-strengthen after each --enrich to verify convergence.
```

**Step 4 — Display the report summary to the user**

After writing to `README.org`, display the same report in the chat so the
user can immediately see what was covered and what remains.

> **Why this phase is mandatory:** without it, deferred sections are invisible
> to all downstream tools (`chorus-strengthen`, `chorus-create-project`).
> The coverage report is the only artefact that tracks corpus → KB completeness.
> `chorus-strengthen` detects rule gaps from project discordances only — it
> cannot detect corpus sections that were never modelled.


## Mode B — Incremental Enrichment (`--enrich` required)

Used **only** when `--enrich` is present in the command.
`<sandbox-name>` must exist and contain a KB.

### ⚠️ WIP checkpoint check — mandatory first step

**Before anything else**, check for a leftover WIP file from a previous incomplete pass:

```bash
WIP="$SANDBOXES/<sandbox-name>/.chorus-wip.md"
```

| File present? | Action |
|---|---|
| **No** → normal | Proceed to Phase B0 |
| **Yes** → previous pass incomplete | Display warning and stop |

If `.chorus-wip.md` exists, display:

```
⚠️  chorus-feed --enrich interrupted — previous pass incomplete
    Sandbox : <sandbox-name>
    WIP file: $SANDBOX/.chorus-wip.md

    A previous --enrich pass was started but never completed (Phase B4.5 was
    not reached — README.org coverage report may be missing or inconsistent).

    Contents of .chorus-wip.md:
    ──────────────────────────────────────────────────────
    <display file content>
    ──────────────────────────────────────────────────────

    Options:
      1. Fix manually: run Phase B4.5 on the previous corpus, then delete
         .chorus-wip.md, then re-run chorus-feed --enrich for the new corpus.
      2. Override: add --force to skip this check and start a new pass
         (the old WIP file will be overwritten — previous pass remains unfinished).

    Recommended: option 1 — ensure KB consistency before proceeding.
```

**`--force` override:** if the user explicitly passed `--force` alongside `--enrich`,
overwrite the existing WIP file and proceed to Phase B0 without stopping.

> **Why this check exists:** the chunking rule (≤ 2 files per turn) splits Mode B
> across multiple conversation turns. If a session ends between turns, the KB can be
> left in a partially consistent state (YAMLs generated but KB org not updated, or
> README coverage report missing). The WIP file is the only reliable signal that a
> previous pass did not reach completion.

### Phase B0 — Read existing KB

**Step 0 — Create WIP checkpoint file**

Before reading any KB file, write `.chorus-wip.md` in the sandbox root:

```markdown
# chorus-feed WIP checkpoint
sandbox: <sandbox-name>
corpus: <corpus-filename>
started: <YYYY-MM-DD>
mode: B
status: IN_PROGRESS

## What this means
A chorus-feed --enrich pass was started but has not yet completed Phase B4.5
(README.org coverage delta report). If this file is still present after the
session ends, the KB may be partially consistent:
- YAML rules and/or Helpers.pm may have been written without the README being updated.
- The * Coverage section of README.org may be missing or refer to sections not yet created.

## How to recover
1. Manually execute Phase B4.5 for the corpus listed above.
2. Verify README.org * Coverage is complete and coherent.
3. Delete this file once Phase B4.5 is confirmed complete.
```

> **One write, no further updates.** This file is written once at the start and
> deleted once at the very end (Phase B4.5 Step 5). It is never updated between phases —
> updating it per phase would re-introduce the same timeout risk it is designed to detect.

1. Read `agent/chorus/index.org` → current pipeline, known agents
2. Read each `agent/chorus/<slug>.org` → Slot dictionary, Rule catalog
3. Read existing YAML files → already codified rules

### Phase B1 — Analyze the new corpus

Classify each rule/prescription from the new corpus into **3 categories**:

| Category | Criterion | Action |
|---|---|---|
| **Refinement** | Concerns a Frame and slots already known | Add rule to an existing agent |
| **Extension** | Concerns new slots of a known Frame | Extend existing agent KB + new YAML rules |
| **New domain** | Concerns Frames or concepts absent from the KB | Create a new agent |

### Phase B2 — Save the new corpus

Number incrementally: `corpus/002-<slug-source>.txt`, `003-...`
Update the `Integrated corpus` table in `index.org`.

### Phase B3 — Apply changes

**Refinement case:**
- Open `agent/chorus/<slug>.org`
- Add the rule to `Rule catalog`
- Update `Slot dictionary` if new slots
- Generate the corresponding YAML file in `rules/<slug>/`
- If the rule requires a helper: add the helper to `Helpers.pm`
  and update `@EXPORT_OK`
- Verify idempotence and order of R<NN> files

**Extension case:**
- Update `Frame catalog` (new slots)
- Update `Slot dictionary`
- Add rules to `Rule catalog`
- Generate the new YAML files
- Add required helpers to `Helpers.pm`
- Verify that new slots do not conflict with those
  of other agents (Slot dictionary of the index)

**New domain case:**
- Apply Mode A (Phases 1 to 5.5) on the fragment only
- Determine the position of the new agent in the pipeline:
  - Does it read a slot set by an existing agent? → after it
  - Does it set a slot consumed by an existing agent? → before it
- Update `index.org`: insert the new agent at the correct position
- ⚠ Verify that the insertion does not break the chain of targeting slots

### Phase B4 — Enrichment closing

Update `README.org`:
- Add the row in `Corpus` (number + file + source + date)
- Update `Agent status` (KB, YAML, Helpers — new or enriched)
- Increment the enrichment counter of each modified agent

**Conditional hash invalidation — only if something changed:**

```
If at least 1 new YAML rule, Helper function, or KB org section was written:
  → Invalidate the KB hash (infrastructure is stale):
     rm -f $SANDBOX/agent/.kb-hash
     rm -f $SANDBOX/.last-check-results.json

Else (corpus already fully integrated — nothing written):
  → Do NOT invalidate the hash.
     The existing infrastructure remains valid.
     Skip Phase B4.5 update of README.org (coverage report already up to date).
     Display only:
       "ℹ️ Nothing to enrich — corpus already fully integrated in the KB.
        The KB hash is preserved. No chorus-check regeneration needed."
     Stop here.
```

### Phase B4.5 — Coverage delta report (mandatory)

**After every Mode B (`--enrich`) execution**, update the `* Coverage` section
of `README.org` and display a delta report to the user.

**Step 1 — Read the existing coverage report**

Read the `* Coverage` section of `README.org` (written by Phase 6.5 or a
previous Phase B4.5). Extract the current `⏭ Deferred` list.

If the `* Coverage` section is absent (sandbox pre-dates this feature) →
run a full Phase 6.5 scan first, then proceed.

**Step 2 — Classify what this `--enrich` pass processed**

For each section in the `⏭ Deferred` list:
- **Promoted to ✅** — at least one new YAML rule or Helper was generated for it
- **Still ⏭** — section was not covered in this pass (state updated reason if changed)
- **Reclassified to ⛔** — on re-reading, the section is not codifiable (explain why)

For any **new section** discovered in the corpus during this pass that was not
in the previous coverage report → add it to the appropriate bucket.

**Step 3 — Update `README.org`**

Replace the `* Coverage` block with the updated version:

```org
* Coverage
  Last updated by chorus-feed --enrich — <date>
  Corpus: <corpus-filename>  (enrichment pass <N>)

** ✅ Integrated (<N_total> rules / tables)
   | Section / Article     | Rules generated          | Added in pass |
   |-----------------------+--------------------------+---------------|
   | §<N> — <title>        | R<NN>-<slug>.yml         | Mode A / B<N> |

** ⏭ Deferred — needs chorus-feed --enrich (<N_remaining> sections)
   | Section / Article     | Reason          | Suggested new rule / agent       |
   |-----------------------+-----------------+----------------------------------|
   | §<N> — <title>        | <reason>        | <RNN-slug or new-agent>          |

** ⛔ Out of scope (<N> sections)
   | Section / Article     | Reason                                  |
   |-----------------------+-----------------------------------------|
   | §<N> — <title>        | informative / external-norm / procedural|

** Next step
   #+BEGIN_EXAMPLE
   # If ⏭ Deferred list is non-empty:
   chorus-feed <sandbox-name> <corpus> --enrich   ← another pass needed

   # Always after --enrich:
   chorus-check <sandbox-name> <any-project.json>
   chorus-strengthen <sandbox-name>
   #+END_EXAMPLE
```

> ⛔ **Règle d'édition atomique — bloc `* Coverage` :**
> Cette étape est **un seul appel `eca__edit_file`** ciblant le bloc `* Coverage`
> en entier — depuis la ligne `* Coverage` jusqu'à la fin du fichier (ou jusqu'au
> prochain heading `*` de même niveau si le README en a un après).
> **Ne jamais découper en plusieurs édits ciblant des sous-headings**
> (`** ⏭ Deferred`, `** Next step`, etc.) : une fois du contenu inséré, ces
> sous-headings peuvent apparaître plusieurs fois dans le fichier, et
> `eca__edit_file` sans `all_occurrences: true` remplace silencieusement la
> **première** occurrence — qui peut être au milieu du bloc qu'on vient d'écrire,
> tronquant tout ce qui suit.
>
> **Pattern correct :**
> `original_content` = le bloc `* Coverage` existant depuis son heading jusqu'à
> la fin du fichier (lu via `eca__read_file` juste avant l'édit).
> `new_content` = le bloc `* Coverage` complet et mis à jour, du heading à la
> dernière ligne.
> **Un seul appel, un seul remplacement, aucun édit de suivi sur le même bloc.**

**Step 4 — Display the delta summary to the user**

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  chorus-feed --enrich — Coverage delta
  Sandbox : <sandbox-name>
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  This pass   : <N_new> new rule(s) / helper(s) generated
  Promoted ✅ : <N_promoted> section(s) now integrated
  Still ⏭    : <N_remaining> section(s) still deferred
  Reclassified⛔: <N_reclassified> section(s) moved out of scope

  ── Promoted this pass ──────────────────────────────
  §<N> — <title>  →  R<NN>-<slug>.yml  [<agent>]
  …

  ── Still deferred ──────────────────────────────────
  §<N> — <title>  (<reason>)
  …

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  <N_remaining> section(s) remain. Run another --enrich pass,
  OR verify with chorus-strengthen that existing rules are sufficient.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

If `N_remaining == 0` → display instead:
```
✅ Full corpus coverage reached — all normative sections integrated or
   explicitly classified as out of scope.
   No further --enrich pass needed.
   Next: chorus-strengthen <sandbox-name> to verify rule quality.
```

**Step 5 — Delete WIP checkpoint file**

Phase B4.5 is now complete. Delete the WIP file to signal successful completion:

```bash
rm -f "$SANDBOXES/<sandbox-name>/.chorus-wip.md"
```

Display confirmation:
```
🔓 WIP checkpoint cleared — $SANDBOX/.chorus-wip.md deleted.
   This --enrich pass is fully complete (Phase B4.5 reached).
```

> **Why deletion is the completion signal:** the WIP file is written at the very
> start (Phase B0 Step 0) and deleted only here, at the very end. Its absence
> is the only reliable proof that a pass completed without interruption.
> Any crash, timeout, or session end between B0 and B4.5 Step 5 leaves the file
> in place — making the next `--enrich` invocation immediately aware of the gap.

> **Convergence criterion:** the `--enrich` loop converges when the
> `⏭ Deferred` list reaches 0. This is the only reliable signal that
> the KB covers the full corpus — `chorus-strengthen` alone cannot
> detect unmodelled corpus sections.

## Mode C — Alias Harvest (`--harvest-aliases <import-report.org>`)

Used **only** when `--harvest-aliases` is present. No `<corpus>` argument is needed.
The sandbox must exist and contain a KB (at least one `<slug>.org` file).

**Purpose:** promote validated project-side terminology (from a past import) into the
KB `** Aliases` tables permanently. Future `chorus-import-project` runs on this sandbox
will resolve these terms at ✅ confidence without re-deriving them.

### Phase C0 — Read existing KB

Read each `$SANDBOX/agent/chorus/<slug>.org` into memory (Slot dictionary, Catalogue
des Frames, current `** Aliases` table). Build a fast-lookup map:
```
alias_map : { canonical_kb_form → set(known_aliases) }
```

### Phase C1 — Parse the import report

Read `<import-report.org>`. Extract the **alignment table** rows where:
- Confidence column = `✅` (certain)
- Decision column = confirmed (not rejected, not pending)

For each such row, collect:
```
(project_term, kb_slot_or_type, kb_value, source_file)
```

Ignore rows with `⚠️`, `❓`, `⛔` or `⬜` confidence — only ✅ mappings are harvested.

### Phase C2 — Deduplicate against existing aliases

For each `(project_term, kb_form)` pair:
- Look up `alias_map[kb_form]`
- If `project_term` (case-insensitive) **already present** → skip (log: "already known")
- If **absent** → mark as new

Output:
```
N_total  : total ✅ rows in the report
N_known  : already present in KB aliases
N_new    : new aliases to integrate
```

If `N_new == 0` → display "Nothing to harvest — all mappings already known in the KB."
and stop.

### Phase C3 — Integrate new aliases into KB

For each new alias, locate the correct `<slug>.org` file:
- Match `kb_slot_or_type` against the `Slot dictionary` and `Catalogue des Frames`
  of each slug to find the owning agent.
- Insert the alias row into the `** Aliases` table of that slug's org file:

```org
| <canonical_kb_form> | <project_term>  | harvested from import-report-NNN.org |
```

If `kb_form` maps to a `type_element` value, also add an `# alias:` comment in the
`Catalogue des Frames` under the matching Frame:
```org
*** montant_porteur
    # alias: "poteau porteur" — harvested from import-report-003.org
```

If no owning slug is found for a mapping → log as unresolved and skip.

### Phase C4 — Harvest closing

1. Invalidate the KB hash:
```bash
rm -f $SANDBOX/agent/.kb-hash
rm -f $SANDBOX/.last-check-results.json
```

2. Display a summary:
```
✅ Alias harvest complete — $SANDBOX

   Report read    : <import-report-NNN.org>
   ✅ rows parsed  : N_total
   Already known  : N_known (skipped)
   New aliases    : N_new integrated

   Modified KB files:
     agent/chorus/<slug1>.org  (+N aliases)
     agent/chorus/<slug2>.org  (+N aliases)

   Next chorus-import-project run on this sandbox will resolve
   these N terms at ✅ confidence without re-asking.
```

3. **Do not** regenerate YAML, Helpers.pm, Feed.pm, or any infrastructure file.
   Mode C modifies only `<slug>.org` files — exclusively the `** Aliases` section.
   The KB hash invalidation ensures `chorus-check` regenerates infrastructure on next run.

| Artifact          | Convention                              | Example                           |
|-------------------|-----------------------------------------|-----------------------------------|
| Sandbox           | `test-<NNN>` or `test-<slug>`           | `test-01`, `test-norme-ec5`       |
| Agent slug        | kebab-case                              | `conformite-fiscale`              |
| KB file           | `<slug>.org`                            | `conformite-fiscale.org`          |
| YAML directory    | `rules/<slug>/`                         | `rules/conformite-fiscale/`       |
| YAML files        | `R<NN>-<slug-rule>.yml`                 | `R01-verif-montant.yml`           |
| **Element type slot** | **always `type_element`** ⛔ never `element_type` / `type` / `kind` | `type_element: montant_porteur` |
| Agent helpers     | `lib/<Namespace>/Agent/<Slug>/Helpers.pm` | `lib/CB/Agent/Ossature/Helpers.pm` |
| Shared helpers    | `lib/<Namespace>/Helpers/Shared.pm`     | `lib/CB/Helpers/Shared.pm`        |
| Initial corpus    | `corpus/001-<slug-source>.txt`          | `corpus/001-dtu-31-2.txt`         |
| Enrichment corpus | `corpus/<NNN>-<slug>.txt`               | `corpus/002-ec5-sect3.txt`        |
| Project namespace | CamelCase, defined at startup           | `MonProjet`                       |

> ⚠ `chorus-feed` never generates: `Feed.pm`, shell Agent module (`build()`),
> `Expert.pm`, `run.pl`. These artifacts are the exclusive responsibility of `chorus-check`.
