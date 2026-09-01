# Diagram 14 — Sizes of Openings and Recesses

**Source:** Approved Document A 2013, §2C29, Page 29-31  
**Corpus:** `004-uk-approved-doc-a-2013-vision.md`  
**KB Reference:** `agent/chorus/wall.org` (Rule R10-opening-factor-x)

---

## Overview

Diagram 14 specifies dimensional criteria for **openings and recesses in external walls** to prevent structural instability. The diagram is a plan view of a wall showing:

- Multiple openings (W₁, W₂, W₃) separated by piers/buttresses (P₁–P₄)
- Corner opening (W₄) with minimum corner pier distance (P₅)
- Total wall length (L) and opening height constraint (H)

---

## Dimensional Constraints — 8 Rules

| Rule # | Parametr | Constraint | Description |
|---|---|---|---|
| **1** | W₁ + W₂ + W₃ | ≤ 2L/3 | Total aggregate opening width must not exceed 2/3 of wall length |
| **2** | W₁, W₂, W₃ | ≤ 3.0 m each | Individual opening width limited to 3 metres |
| **3** | P₁ | ≥ W₁/X | Pier before first opening must be ≥ first opening width divided by Factor X |
| **4** | P₂ | ≥ (W₁ + W₂)/X | Pier between first and second opening ≥ combined widths / X |
| **5** | P₃ | ≥ (W₂ + W₃)/X | Pier between second and third opening ≥ combined widths / X |
| **6** | P₄ | ≥ W₃/X | Pier after last opening ≥ last opening width / X |
| **7** | P₅ | ≥ max(W₄/X, 665 mm) | **Corner pier** — minimum 665 mm or W₄/X, whichever is greater |
| **8** | H (height) | ≤ 2.1 m | Opening height must not exceed 2.1 metres |

---

## Geometric Parameters Extracted

### Wall & Opening Dimensions

| Symbol | Parameter | Unit | Notes |
|---|---|---|---|
| **L** | Wall length | metres | Total length of the wall section being assessed |
| **H** | Opening height | metres | Maximum opening height; constrained to ≤ 2.1m |
| **W₁** | First opening width | metres | Width of opening 1 |
| **W₂** | Second opening width | metres | Width of opening 2 |
| **W₃** | Third opening width (or recess) | metres | Width of opening/recess 3 |
| **W₄** | Corner opening width | metres | Width of opening at corner (for P₅ calculation) |
| **Σ(W)** | Aggregate opening width | metres | W₁ + W₂ + W₃ (sum of first three) |

### Pier/Buttress Distances

| Symbol | Parameter | Unit | Notes |
|---|---|---|---|
| **P₁** | Pier before W₁ | mm | Distance/thickness of first pier (section perpendicular to wall) |
| **P₂** | Pier between W₁ and W₂ | mm | Distance/thickness of middle pier |
| **P₃** | Pier between W₂ and W₃ | mm | Distance/thickness of middle-right pier |
| **P₄** | Pier after W₃ | mm | Distance/thickness of last pier |
| **P₅** | Corner pier distance | mm | Distance from corner to nearest opening edge; minimum 665 mm |

### Load Factor

| Symbol | Parameter | Unit | Range | Notes |
|---|---|---|---|---|
| **X** | Factor X | dimensionless | 3–6 | Depends on roof/floor configuration; from Table 8 or defaults to 6 |

---

## Table 8 — Value of Factor 'X'

**Source:** §2C29, Table 8, Page 31

Factor X determines the **pier-to-opening width ratio** and varies by roof configuration, roof span, wall thickness, and floor span direction.

### Roof Spans Parallel to Wall

| Wall Thickness | Max Roof Span | Timber Floor Span ≤ 4.5m | Timber Floor Span ≤ 6.0m | Concrete Floor (Parallel) ≤ 4.5m | Concrete Floor (Parallel) ≤ 6.0m |
|---|---|---|---|---|---|
| **100 mm** | N/A | **6** | **6** | **6** | **6** |
| **90 mm** | N/A | **6** | **6** | **6** | **5** |

### Timber Roof Spans Into Wall (9m max)

| Wall Thickness | Max Roof Span | Timber Floor Span ≤ 4.5m | Timber Floor Span ≤ 6.0m | Concrete Floor (Into) ≤ 4.5m | Concrete Floor (Into) ≤ 6.0m |
|---|---|---|---|---|---|
| **100 mm** | 9 | **6** | **6** | **5** | **4** |
| **90 mm** | 9 | **6** | **4** | **4** | **3** |

### Interpretation Rules

1. **Rule 8 of Diagram 14:** Factor X defaults to **6** if:
   - Declared compressive strength of bricks/blocks (loaded leaf in cavity walls) ≥ **7.3 N/mm²**
   - This is a conservative safe default

2. **Roof span direction** matters:
   - **Parallel to wall** → higher Factor X (less restrictive piers)
   - **Into wall** (timber only) → lower Factor X (more restrictive piers)

3. **Floor type** affects the ratio:
   - Concrete floors are more favorable than timber
   - Longer concrete spans permit lower Factor X values

---

## KB Slots — Data Model

### Input Slots (Read from Feed)

The following slots are read by **Rule R10-opening-factor-x** from the Frame:

| Slot Name | Type | Scope | Notes |
|---|---|---|---|
| `length_m` | float | external_wall | Wall length L (metres) |
| `openings_total_width_m` | float | external_wall | Σ(W₁+W₂+W₃) — **pre-aggregated** by feed |
| `opening_max_individual_m` | float | external_wall | max(W₁, W₂, W₃) — largest individual opening |
| `opening_height_m` | float | external_wall | max opening height H (metres); optional |
| `corner_pier_dist_mm` | float | external_wall | P₅ distance in mm (from corner) |
| `opening_factor_x_w4_m` | float | external_wall | W₄ — corner opening width (metres) |
| `factor_x` | integer (3–6) | external_wall | Factor X from Table 8; defaults to 6 if absent |

### Output Slots (Written by Rule)

| Slot Name | Type | Value | Purpose |
|---|---|---|---|
| `opening_factor_ok` | enum | 'YES' / 'NO' | Validation result: all constraints met? |
| `wall_violations` | string | violation list | Cumulative list of constraint breaches |
| `wall_ok` | enum | 'NO' (if violated) | Upstream flag; set to 'NO' if any opening rule fails |

---

## Implementation Status in KB

### ✅ Implemented Rules (1–2, 7–8)

These four constraints are **fully codified** in `rule/wall/R10-opening-factor-x.yml`:

```perl
# Rule 1: Total openings ≤ 2L/3
if ($L > 0 && $tot > (2 * $L / 3)) {
    push @viol, "openings total ${tot}m > 2L/3 = ${max_tot}m (§2C29 Diagram 14 rule 1)";
}

# Rule 2: Individual opening ≤ 3m
if ($wmax > 3.0) {
    push @viol, "opening width ${wmax}m > 3.0m max (§2C29 Diagram 14 rule 2)";
}

# Rule 8: Height ≤ 2.1m
if (defined $hmax && $hmax > 2.1) {
    push @viol, "opening height ${hmax}m > 2.1m max (§2C29 Diagram 14)";
}

# Rule 7: Corner pier P₅ ≥ max(W₄/X, 665mm)
if (defined $p5 && $fx > 0) {
    my $min_p5_ratio = ($w4 > 0) ? ($w4 * 1000 / $fx) : 0;
    my $min_p5 = ($min_p5_ratio > 665) ? $min_p5_ratio : 665;
    if ($p5 < $min_p5) {
        push @viol, "corner pier P5 ${p5}mm < max(W4/X, 665mm) = ${ms}mm (§2C29 Diagram 14 rule 7)";
    }
}
```

### ❌ Not Implemented Rules (3–6)

These **pier-to-opening ratio checks** are **not yet codified**:

| Rule | Constraint | Reason for Non-Implementation |
|---|---|---|
| **3** | P₁ ≥ W₁/X | Requires individual W₁ value (not aggregated); not provided by feed |
| **4** | P₂ ≥ (W₁+W₂)/X | Requires per-pier position tracking; complex geometry not modeled |
| **5** | P₃ ≥ (W₂+W₃)/X | Requires sequential pier enumeration; not in current data model |
| **6** | P₄ ≥ W₃/X | Requires final pier measurement; not extracted from corpus |

**KB Note** (from `wall.org`):
> « Detailed per-pier ratio checks (Diagram 14 rules 3–6) need individual P1-P4/W1-W4 slots.  
> The feed must provide pre-aggregated opening widths (W1+W2+W3 summed into  
> openings_total_width_m). Detailed per-pier ratio checks require individual P1-P4 and W1-W4  
> values — codifiable with feed support. »

---

## Extraction Completeness

### Fully Extracted ✅

- Rule 1 constraint (aggregate width)
- Rule 2 constraint (individual width max)
- Rule 8 constraint (height max)
- Rule 7 constraint (corner pier + Factor X)
- Table 8 Factor X lookup matrix
- Geometric parameters: L, W₁–W₄, H, P₅

### Partially Extracted ⚠️

- Factor X Table: matrix structure extracted, **but default value (6) is hardcoded**; no Table 8 lookup helper implemented yet

### Not Extracted ❌

- Rules 3–6 (individual pier constraints P₁–P₄)
- Detailed wall-section geometry (pier positions not tracked in KB)
- Section diagrams showing pier/opening relationships (referenced but not encoded)

---

## Feed Data Requirements for Full Implementation

To implement Rules 3–6 and achieve **100% coverage** of Diagram 14, the feed must provide:

### Per-Opening Data (granular level)

```json
{
  "openings": [
    {
      "id": "opening_1",
      "width_m": 1.5,
      "height_m": 2.0,
      "position": "left"
    },
    {
      "id": "opening_2",
      "width_m": 2.0,
      "height_m": 2.1,
      "position": "center"
    },
    {
      "id": "opening_3",
      "width_m": 1.2,
      "height_m": 1.8,
      "position": "right"
    }
  ],
  "piers": [
    { "id": "P1", "distance_mm": 200 },
    { "id": "P2", "distance_mm": 350 },
    { "id": "P3", "distance_mm": 400 },
    { "id": "P4", "distance_mm": 250 }
  ],
  "corner_pier": {
    "id": "P5",
    "distance_mm": 700,
    "corner_opening_width_m": 1.8
  }
}
```

### Aggregated Data (current, sufficient for Rules 1–2, 7–8)

```json
{
  "length_m": 8.0,
  "openings_total_width_m": 4.7,
  "opening_max_individual_m": 2.0,
  "opening_height_m": 2.1,
  "opening_factor_x_w4_m": 1.8,
  "corner_pier_dist_mm": 700,
  "factor_x": 5
}
```

---

## Related KB Rules & Helpers

### Rule Catalog

| Rule ID | Intent | Scope | Status |
|---|---|---|---|
| **R09-buttressing-opening** | Openings in buttressing walls (§2C26) | buttressing_wall | ✅ Implemented |
| **R10-opening-factor-x** | Opening dimensional criteria (§2C29) | external_wall | ✅ Implemented (partial) |
| **R11-chase-depth** | Chase/recess depth limits (§2C30) | external_wall, internal_wall | ✅ Implemented |
| **R15-small-building-wall** | Non-residential building openings (§2C38) | external_wall | ✅ Implemented |

### Helper Functions

| Helper | Purpose | Returns | Exported |
|---|---|---|---|
| `factor_x_table8` | Lookup Factor X from Table 8 | 3–6 | Not yet implemented |
| (future) `pier_ratio_check` | Validate P1–P4 ratios (Rules 3–6) | YES/NO | Planned |

---

## References & Cross-Links

### Within Corpus

- `004-uk-approved-doc-a-2013-vision.md`, Lines 1762–1804
  - Diagram 14 figure description
  - Table 8 layout and values

### Within KB

- `agent/chorus/wall.org`
  - Lines 715–728: R10 rule definition
  - Lines 843–857: Table 8 description
  - Lines 887–905: Pitfalls & constraints

### Within Rules

- `rules/wall/R10-opening-factor-x.yml`
  - Lines 1–62: Full rule implementation (Perl ACTION code)

---

## Amendments & Future Work

- [ ] Implement `factor_x_table8()` helper for dynamic Table 8 lookup
- [ ] Add per-opening granular data model (W1/P1–P4 individual slots)
- [ ] Code Rules 3–6 (pier ratio validation)
- [ ] Add pier position tracking in feed (left/center/right)
- [ ] Cross-validate with Rule R09 (buttressing wall constraints §2C26)

---

**Document Generated:** 2025-07-17  
**Last Updated:** (initial version)  
**Status:** Reference & Extraction Analysis for KB Test-02 Sandbox
