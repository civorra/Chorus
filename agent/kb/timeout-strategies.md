# Strategies to Avoid `java.net.ConnectException` in Chorus Skills

> **Root cause:** The main ECA agent generates too much content in a single turn
> → the HTTP streaming session exceeds the backend Java timeout → `ConnectException`.
> This is **NOT a network problem** — it's a volume-per-turn issue.

---

## Reference Limits (main agent, per turn)

| Operation Type | Limit per turn |
|---|---|
| `eca__write_file` | **1 file** if > 80 lines; **2 files** if ≤ 80 lines each |
| `eca__read_file` | unlimited (read-only, fast) |
| YAML rule generation | **2 `.yml` files** maximum |
| `Helpers.pm` generation | **1 file** per turn |

---

## Strategy 1: Use Sub-agents (`eca__spawn_agent`)

**Best for:** Large JSON generation (chorus-create-project, chorus-check --all)

### When to use sub-agents
- Task involves **one large output** (>200 lines single file)
- OR spawning **N independent tasks** (N > 2) in parallel
- Estimated execution time: **2–5 minutes per sub-task**

### How it works
```
Main agent (orchestrator)
  ├─ Sub-agent 1: spawn with --strategy iso
  ├─ Sub-agent 2: spawn with --strategy edges
  ├─ Sub-agent 3: spawn with --strategy cross
  └─ Sub-agent 4: spawn with --strategy scale
```

Each sub-agent has:
- Its own IDE session and token budget (~200k tokens)
- No timeout risk from output volume
- Shared context (KB, sandbox path) passed in the task description

### Code pattern

```
eca__spawn_agent:
  agent: "general"
  activity: "generate iso strategy"
  task: |
    Sandbox: /home/civ/Documents/DEV/Chorus/sandboxes/test-06-copyright-EU
    
    Run: chorus-create-project test-06-copyright-EU --strategy iso
    
    Return: the full JSON file content to the main agent via a RETURN block.
```

### Limitations
- ⛔ Cannot spawn a sub-agent from within a sub-agent (no nesting)
- ⛔ Do not use for file editing (eca__edit_file) — stick to main agent for that
- ⛔ Sub-agents cannot update the task list (eca__task)

---

## Strategy 2: Chunking (Sequential output per turn)

**Best for:** File generation/modification in the main agent when sub-agents are not appropriate

### Pattern: small turns + loop
```
Turn 1: Generate + write projet-rules-iso.json (160 elements)
        Pause. Main agent token budget reset.

Turn 2: Generate + write projet-edges.json (120 elements)
        Pause.

Turn 3: Generate + write projet-cross.json (80 elements)
        Pause.

Turn 4: Generate + write projet-scale.json (250 elements)
```

Each turn handles **≤ 1 large file** (stay under ~8,000 output tokens).

### When to use chunking
- Cannot spawn sub-agents (architectural reason)
- OR prefer sequential determinism (debugging, reproducibility)
- Task duration is acceptable (4 turns = 4 user prompts)

### Code pattern

```python
# Turn 1 — iso
Generate projet-rules-iso.json (156 elements, 50 KB)
eca__write_file("...projet-rules-iso.json", json_content)
# Done. User says "next" or the turn ends.

# Turn 2 — edges
Load iso results as context (lightweight reference)
Generate projet-edges.json (120 elements, 40 KB)
eca__write_file("...projet-edges.json", json_content)
```

### Preventing timeout in chunking mode
- Write **exactly 1 large file per turn** (not 2)
- Keep thinking/analysis brief (no extensive validation)
- Delegate validation to `chorus-check --all` (separate turn)

---

## Strategy 3: Hybrid (Recommended for test-06-copyright-EU)

**Use sub-agents for generation, main agent for orchestration & validation.**

### Workflow

```
Turn 1 (Main agent):
  ├─ Read KB once (Phase 0 of chorus-create-project)
  ├─ Spawn 4 sub-agents in parallel
  │   ├─ Sub 1: --strategy iso   (output: projet-rules-iso.json)
  │   ├─ Sub 2: --strategy edges (output: projet-edges.json)
  │   ├─ Sub 3: --strategy cross (output: projet-cross.json)
  │   └─ Sub 4: --strategy scale (output: projet-scale.json)
  └─ Collect results

Turn 2 (Main agent):
  ├─ Verify JSON syntax (python3 -c "import json; json.load(...)")
  ├─ Run chorus-check --all (or delegate to new turn)
  └─ Summary report
```

**Why this works:**
- Main agent: reads KB once (~5–6 KB input), spawns 4 tasks → low output volume
- Sub-agents: each generates 1 large JSON file in isolation → no timeout risk
- Output generation is parallelized → wall-clock time ÷ 4

---

## Specific recommendation: chorus-create-project --batch

Given the **test-06-copyright-EU sandbox:**
- KB size: 480 KB
- 78 rules → ~500–700 elements across 4 strategies
- Estimated tokens per strategy: ~18–24K (mostly output)

### ❌ Don't do this
```
chorus-create-project test-06-copyright-EU --batch
  # Main agent spawns 4 sub-agents sequentially/in parallel
  # Each sub-agent outputs ~100–200 KB JSON
  # If the spawn context is too large or output handling is naive → timeout
```

### ✅ Do this instead

**Option A: 4 separate sessions (guaranteed safe, slowest wall-clock)**
```
Session 1: chorus-create-project test-06-copyright-EU --strategy iso
Session 2: chorus-create-project test-06-copyright-EU --strategy edges
Session 3: chorus-create-project test-06-copyright-EU --strategy cross
Session 4: chorus-create-project test-06-copyright-EU --strategy scale

Then:      chorus-check test-06-copyright-EU --all
           chorus-strengthen test-06-copyright-EU
```

**Option B: Sub-agents from main (fast, clean, modern)**
```
Single session:
  chorus-create-project test-06-copyright-EU --batch
  
[ECA implementation:]
  Main agent spawns 4 sub-agents (each runs --strategy <slug>)
  → each sub-agent has 200K token budget
  → no timeout risk
  → results returned to main for assembly
```

**Option C: Chunked in main agent (moderate, sequential)**
```
Turn 1: --strategy iso   + write file
Turn 2: --strategy edges + write file
Turn 3: --strategy cross + write file
Turn 4: --strategy scale + write file
```

---

## Debugging ConnectException

If you still hit `java.net.ConnectException`:

1. **Check output volume in the last turn** — did you:
   - Write 2+ large files in one turn? → split into separate turns
   - Generate >10K output tokens? → reduce output or use sub-agents
   - Read 10+ large files before writing? → inter-leave read/write

2. **Check input before output** — did you:
   - Read a 400+ KB file, then immediately generate 200+ KB output in the same turn?
   - → read in turn N, generate in turn N+1

3. **Use sub-agents if main agent output exceeds 8–10K tokens** — don't chunk in main,
   spawn parallel sub-agents instead.

4. **Check the IDE logs** (`~/.config/eca/logs/`) for the actual error timestamp and token count.

---

## Chorus Skills anti-timeout rules (already implemented)

| Skill | Strategy | Notes |
|---|---|---|
| `chorus-check --all` | Sub-agents per file | Each `projet-*.json` → separate sub-agent spawn |
| `chorus-strengthen` | Phase 1.1 cache | Cached results = 0 tokens; fallback Phase 1.2 = sub-agents |
| `chorus-create-project --batch` | **Sub-agents per strategy** | Recommended: spawn 4 sub-agents (iso, edges, cross, scale) |
| `chorus-feed` | Chunking + single file write | Max 1 YAML per turn; Helpers.pm in separate turn |

---

## Summary table: when to use which strategy

| Scenario | Use | Reasoning |
|---|---|---|
| Large JSON generation (>5 strategies) | Sub-agents | Parallel execution, no timeout risk |
| File editing in main agent | Chunking | ≤1 large file per turn |
| Small independent tasks (N < 5) | Chunking | Minimal overhead |
| KB reading > 100 KB | OK in main agent | Doesn't consume output tokens |
| Hybrid (read + spawn) | Sub-agents | Main orchestrates; subs generate |
| Debugging/reproducibility | Chunking | Easier to track state between turns |

