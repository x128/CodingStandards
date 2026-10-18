---
description: Write THEORY.md — which scientific fields the concepts of a project come from, and how its stages map to known operations. Use when asked for the theory behind a project, or while planning one.
---

# Theory Skill

Writes THEORY.md for a project: which scientific fields its domain concepts come from, and how
each stage of the project is an instance of a known operation. A theoretical term explains a
concept; it never renames it — code, tasks and the plan keep the project's one name.

## Instructions

1. **The concepts.** From what there is — intake answers, the plan, the code, documents — list the
   domain concepts, loops, data structures and operations. With a path, only that part. A new
   project has no code yet: take the terms of the plan.
2. **The fields.** Find every field that applies, not just one, for example:

   | Field | When the project has |
   |---|---|
   | Bayesian inference | beliefs, uncertainty, updates from data |
   | Reinforcement learning | agents, rewards, policies, exploration |
   | Information theory | entropy, compression, information gain |
   | Optimization | objectives, constraints, search |
   | Constraint satisfaction | hard and soft constraints, propagation |
   | Graph theory | networks, flow, connectivity, traversal |
   | Decision theory | utility, risk, trade-offs |
   | Active learning | query strategies, labelling budget |
   | Control theory | feedback loops, stability, set points |
   | Game theory | several agents, equilibria |
   | Formal languages | grammars, parsing, automata |
   | Signal processing | filtering, frequency, noise |
   | Computational geometry | spatial layouts, packing |

3. **Write THEORY.md**, or update it and delete what no longer holds:
   - the mapping, one line each: `project term = **theoretical term**`; and each term of a chosen
     field that the project has no counterpart for, marked as missing;
   - each stage of the project: what it does, its formal objective, its method, and why it works;
   - each key type of the code and its theoretical role;
   - the unknowns of the project and their kinds;
   - how uncertainty is measured and reduced;
   - where the theory could guide the next work, grounded in the project's plan;
   - a glossary of every theoretical term the document uses: term, symbol, definition.

   Every claim points to a real type, function or data flow in the code, or, before there is code,
   to the section of the plan. Use formulas only where they make a mapping clearer.
4. **Point to it:** one line in the project's `CLAUDE.md` that names THEORY.md.

## Allowed Prompts
- Read source files and project documents
- Write THEORY.md and one line in CLAUDE.md

## Example Usage

```
/theory
/theory src/solver/
```
