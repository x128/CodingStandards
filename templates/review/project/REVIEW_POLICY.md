# Review Policy

> The maintainer's rubric for this project: judgments no tool can make.
> Loaded into the maintainer's context on every run.
>
> This file belongs to the project, not to the CodingStandards submodule.
> See `CodingStandards/MAINTAINER_TRAINING.md` for how rules get written and
> maintained.

**Rules of this file:**

- One rule per decision you had to make twice. Ids (`R-nnn`) are never reused.
- `Level` sets severity: `MUST` → blocker, `SHOULD` → major, `MAY` → minor.
- If a linter could enforce it, it does not belong here — put it in `gates.sh`.
- Target 20–40 rules. When a new rule is a special case of an existing one,
  edit the existing one.
- Prune monthly: delete rules that never fire, merge duplicates.

---

## What is NOT in this file

Out-of-scope findings and unproven possible-confidence findings are **built-in
decision rules 5 and 6** in the maintainer prompt. Do not restate them here.

A policy rule matches *before* those rules (rule 3 wins over 5 and 6), so a rule
duplicating a built-in makes the built-in unreachable and collapses every
verdict to `decision_rule: policy-rule` — which destroys the one field that
tells you *why* things are being rejected when you later analyse the log.

Write a rule here only to **override** a built-in for a specific scope — for
example "possible-confidence memory-safety findings in `src/parser/**` are
accepted anyway". That is a real rule. "Reject out-of-scope findings" is not.

---

## Project rules

### R-001: Performance findings need a measurement

- **Level**: SHOULD
- **Applies to**: all
- **Verdict**: reject without a benchmark or a complexity argument on a
  documented hot path
- **Rationale**: Speculative optimization costs more in review and complexity
  than it saves at runtime.
- **Added**: <date>, with the pipeline

> Everything below is an example of the shape a real rule takes. Delete them and
> write your own.

### R-002: Every tenant-scoped query filters on tenant id

- **Level**: MUST
- **Applies to**: `src/db/**`
- **Verdict**: accept, severity blocker
- **Rationale**: Cross-tenant data leak. No test covers every query, so this
  cannot move to Layer 0.
- **Added**: <date>, after T-0nn / F-0nn

### R-003: Internal utilities are not documented

- **Level**: MAY
- **Applies to**: `src/internal/**`
- **Verdict**: reject missing-documentation findings
- **Rationale**: Documentation churn on code with no external consumers. Public
  API is a different matter — see R-004.
- **Added**: <date>, after T-0nn / F-0nn

### R-004: Public API changes without documentation are blocked

- **Level**: MUST
- **Applies to**: exported symbols in `src/api/**`
- **Verdict**: accept, severity blocker
- **Overrides**: R-003
- **Rationale**: The API surface is the contract with other teams.
- **Added**: <date>, after T-0nn / F-0nn

---

## Worked examples

> Two or three canonical, project-specific examples for the maintainer. Replace
> them as your judgment sharpens — do not accumulate. If you are tempted to add
> a fourth, the case probably needs a rule instead.

### Rejected: a rule exists, and the code already satisfies it

```json
Finding: {"id": "F-012", "file": "src/db/report.rs", "category": "bug",
          "severity": "major", "confidence": "possible",
          "evidence": "query may return rows from other tenants"}
Verdict: {"finding_id": "F-012", "verdict": "reject", "severity": "minor",
          "decision_rule": "unproven-possible",
          "reason": "R-002 requires a tenant_id filter and this query has one at line 41,
                     so the rule is satisfied and does not fire. Possible confidence with
                     no counterexample falls to decision rule 6."}
```

Note which `decision_rule` this carries: a policy rule that is *satisfied* does
not fire, so the built-in rule decides — and the log stays informative.
