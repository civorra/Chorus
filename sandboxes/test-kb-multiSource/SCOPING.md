# Corpus scoping — test-kb-multiSource

## Corpus reviewed
| File | Pages / size | Notes |
|---|---|---|
| corpus/001-cir-binding.md | ~1p | CIR-1.0 — binding regulation, load + crypto requirements |
| corpus/002-arf-toolbox.md | ~1p | ARF-2.1 — technical toolbox, algorithm table + guidance |

## Agents (proposed pipeline order)
| # | Slug | Intent | Consumes (slots) | Produces (slots) |
|---|---|---|---|---|
| 1 | agent-load | Load conformance — CIR Art.5 — P1/P2/P3 minimum load thresholds in Newtons | — | load_ok, motif_load |
| 2 | agent-algo | Cryptographic algorithm compliance — CIR Art.6 / ARF §3.2 — approved list + minimum key length | — | algo_ok, motif_algo |

## Domain Frames
| Frame | Key slots | Notes |
|---|---|---|
| widget | type_element, perf_class, load_n, algorithm, key_length_bits | persistent test element |

## Inter-Frame relationships
(none for this test sandbox)

## Control slots
| Frame.slot | Control slot | Corpus justification |
|---|---|---|
| widget.load_n | _NEEDED | CIR Art.5 — "minimum load" implies derivation possible from perf_class if absent |

## BOARD slots
(none for this test sandbox)

## Pre-checks performed
- [x] Rotated-header matrix table scan — none found (ARF §3.2 table has borders)
- [x] Grammar/identifier alternate-form search — perf_class: P1/P2/P3 only, no alternate form documented

## Corpus section assignment
(filled by chorus-corpus-scoping Phase 2)

## Open questions for the operator
(none — synthetic corpus, all sections designed explicitly)

## Status
`CONFIRMED — test`
