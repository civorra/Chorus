# Skill — chorus-schema-export

> Trigger: `chorus-schema-export <sandbox-name>`
> Agent: `architect`
>
> **Single responsibility: derive a canonical, versioned JSON Schema contract
> from a stabilised sandbox KB — the machine-readable shape a project JSON
> must satisfy, independent of any specific project instance.**
>
> Design rationale: `agent/org/proposals/production-packaging.org`
>
> Prerequisite: `chorus-check <sandbox-name> --all` must have passed (KB
> stabilised, infrastructure generated, `.kb-hash` present).


## Step 0 — Prerequisite check

```
$SANDBOX/agent/.kb-hash              ← must exist
$SANDBOX/agent/.last-check-results.json  ← must exist, converged: true recommended
```

If `.kb-hash` is absent → stop and report:
`"Run chorus-check <sandbox-name> --all first — KB not stabilised."`

If `.last-check-results.json` is present but `converged: false` → warn but
continue (schema export does not require business-rule convergence, only
infrastructure presence — the two are decoupled by design).


## Step 1 — Reuse Phase 1.5 slot analysis (chorus-check)

Do **not** duplicate the YAML-scanning logic. Re-run the exact same
mechanical procedure as `chorus-check.md § Phase 1.5` to obtain, for every
`type_element` in the pipeline:

- `input_slots[T]` — slots that must come from the project JSON (targeting
  slot + non-computed data slots)
- `computed_slots[T]` — slots written by rules (excluded from the contract's
  required properties — a producing system's adapter must never need to
  guess these)


## Step 2 — Extract value domains (enums)

For each slot in `input_slots[T]`, read the KB org `Frame Catalogue` entry
(`$SANDBOX/agent/chorus/<slug>.org`) for that slot's `Possible values`
column.

- If the column lists a closed set (e.g. `OK/KO/SKIP`, `1/2/3/4`) → emit a
  JSON Schema `enum` constraint.
- If the column says `free` / `str` / unconstrained → no `enum`, just the
  declared `type` (`string`, `number`, `boolean`, `array`).
- If ambiguous → do not force an enum; note it in the export report as a
  candidate for KB org refinement (do not block export).


## Step 3 — Generate the JSON Schema

Write `$SANDBOX/dist/schema-<slug>-<kb_hash8>.json` (create `dist/` if
absent). `<kb_hash8>` = first 8 hex chars of the content of `agent/.kb-hash`.

Shape (draft-07 style, adapt as needed):

```json
{
  "$id": "chorus://<sandbox-name>/schema-<kb_hash8>",
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "<sandbox-name> project contract",
  "type": "object",
  "properties": {
    "projet": { "type": "string" },
    "elements": {
      "type": "array",
      "items": {
        "oneOf": [
          {
            "type": "object",
            "properties": {
              "id": { "type": "string" },
              "type_element": { "const": "<type1>" },
              "<slot_a>": { "type": "string", "enum": ["...", "..."] },
              "<slot_b>": { "type": "number" }
            },
            "required": ["id", "type_element", "<slot_a>", "<slot_b>"],
            "additionalProperties": true
          }
        ]
      }
    }
  },
  "required": ["projet", "elements"]
}
```

Notes:
- `additionalProperties: true` on each branch — a producing system may
  attach extra metadata (traceability fields, source IDs) that Chorus
  ignores; the contract only enforces the minimum Chorus needs.
- One `oneOf` branch per `type_element`; `const` discriminates the branch.
- Do **not** include `computed_slots` anywhere in `required` or `properties`
  as mandatory — if listed at all (for documentation), mark them outside
  `required`.


## Step 4 — Drift classification against previous schema (if any)

```bash
ls $SANDBOX/dist/schema-<slug>-*.json 2>/dev/null
```

If a previous schema exists, diff the new one against the most recent
previous version:

- **Additive**: new optional properties, new enum values added, new
  `oneOf` branch (new type_element) → minor version bump recommendation
- **Breaking**: new required property, removed property, narrowed enum,
  removed `oneOf` branch → major version bump recommendation

Report the classification — do not auto-decide a semantic version number,
surface it for human confirmation (`chorus-schema-export` does not write
git tags).


## Step 5 — Report

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  chorus-schema-export  <sandbox-name>
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  KB hash        : <kb_hash8>…
  Output         : dist/schema-<slug>-<kb_hash8>.json
  Types covered  : N  (<type1>, <type2>, …)
  Ambiguous enums: N  (see notes below — candidates for KB refinement)
  Drift vs prev  : none | additive | breaking
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

If `Drift vs prev = breaking` → recommend:
```
  Next step: bump producing-system adapter major version before packaging.
```


## Relationship to `chorus-check --package`

`chorus-schema-export` produces the contract; `chorus-check --package
<version>` (see `chorus-check.md`) consumes it to build the frozen,
CI-deployable `dist/<version>/` artefact (schema + infrastructure +
manifest). Run `chorus-schema-export` first, then `--package`.
