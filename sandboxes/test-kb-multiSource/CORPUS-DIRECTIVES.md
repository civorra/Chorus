# Corpus directives — test-kb-multiSource

## Sources
| Source | Type | Version pinned | no_auto_rules |
|---|---|---|---|
| CIR-1.0 | binding | v1.0 @ 2025-01 | false |
| ARF-2.1 | technical-reference | v2.1 @ 2025-03 (referenced by CIR-1.0 Art.6) | partial |

## Version pinning notes
- CIR-1.0 references ARF at exactly v2.1 (2025-03). Do not follow ARF live/latest.
  Any future ARF revision (v2.2+) requires an explicit CIR update to be in scope.

## no_auto_rules justification
- CIR-1.0 : binding regulation — all normative articles generate YAML rules.
- ARF-2.1 §3.2 : rule-generating — directly referenced by CIR Art.6, table is opposable.
- ARF-2.1 §3.1 : no_auto_rules — class definitions only, feeds thesaurus (P1/P2/P3 synonyms).
- ARF-2.1 §4.1 : no_auto_rules — implementation guidance prose, no verifiable threshold.
- ARF-2.1 Scope, Annexes : no_auto_rules — informative.

## Thesaurus seed
| Term A | Term B | Same concept? |
|---|---|---|
| performance class | grade | yes — CIR uses "performance class", potential KB alias "grade" |
| certified widget | widget | yes — "certified widget" is the CIR term, "widget" the short form |
| approved algorithm | whitelisted algorithm | yes — equivalent terms across documents |

## Cross-reference format
CIR-1.0 Art.<N> ⇒ ARF-2.1 §<N>
Example: `CIR-1.0 Art.6 ⇒ ARF-2.1 §3.2 Table 3.2-1`
