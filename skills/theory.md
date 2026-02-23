# Theory Skill

Generate a theoretical foundation document (THEORY.md) that maps a project's domain concepts to their scientific roots.

## Instructions

When invoked, generate a THEORY.md for the project:

1. **Understand the project's concepts** — from whatever is available: intake answers, plan drafts, existing code, documentation. Identify the domain concepts, loops, data structures, and operations. On a new project the vocabulary and its theoretical roots are built together; on an existing project, map what's already there.

2. **Identify relevant theoretical frameworks** — not just one. Look for all that apply:

| Framework | Relevant when the project has... |
|---|---|
| Bayesian inference | Beliefs, uncertainty, priors, updates from data |
| Reinforcement learning | Agents, rewards, policies, exploration/exploitation |
| Information theory | Entropy, compression, information gain, channel capacity |
| Optimization | Objectives, constraints, search, gradients, feasibility |
| Constraint satisfaction | Hard/soft constraints, variable domains, propagation |
| Graph theory | Networks, adjacency, flow, connectivity, traversal |
| Decision theory | Utility, risk, tradeoffs, rational choice |
| Active learning | Query strategies, labelling budget, pool/stream |
| Probabilistic programming | Generative models, conditioning, inference engines |
| Control theory | Feedback loops, stability, setpoints, PID |
| Game theory | Multi-agent, equilibria, mechanism design |
| Formal language theory | Grammars, parsing, generation, automata |
| Signal processing | Filtering, frequency analysis, noise |
| Computational geometry | Spatial layouts, packing, Voronoi, convex hulls |

3. **Build the mapping** — for every project concept, find its theoretical name. For every relevant theoretical concept, find its project counterpart. The mapping is the core of the document.

Format as `project term = **theoretical term**`:
```
constraint state = **belief state** P(θ | D₁..Dₜ)
user input = **observation**, a Bayesian update
generated layout = **posterior sample**, a draw from P(geometry | B(t))
```

The theoretical terms become part of the project's vocabulary — alongside UX terms, developer terms, platform terms, and everything else the project uses.

4. **Document each stage/loop** — show how each phase of the project's pipeline is an instance of a theoretical operation:

```
### 2.1 Gap Analysis — "What to ask next"

| Aspect | Detail |
|---|---|
| **Variables** | The set of unresolved dimensions of θ |
| **Objective** | Maximise expected information gain |
| **Method** | LLM approximates mutual information I(θ; D) |
| **Output** | Ranked list sorted by expected posterior compression |

This is **optimal experiment design** / **active learning**.
```

Each stage gets: what it does, why it works, the formal objective, and the method.

5. **Map data structures** — every key class/type in the codebase has a theoretical role:

| Codebase class | Theoretical role |
|---|---|
| `ConstraintState` | The full belief state B(t) |
| `ConstraintItem` | One marginal distribution in the joint posterior |
| `ZoneLayout` | One posterior sample — a point in geometry space |

6. **Document the variable space** — what are the unknowns? What types (discrete, continuous, categorical, structural)? What scopes? This connects the project's data model to the theoretical parameter space.

7. **Cover uncertainty** — how does the project measure, represent, and reduce uncertainty? Map to entropy, variance, confidence, information gain as appropriate.

8. **Future extensions** — where could the theoretical framework guide future work? Learned priors, gradient methods, amortised inference, etc. Keep it grounded in the project's actual trajectory.

9. **Write the glossary** — every term that appears in the document gets a row:

| Term | Symbol | Definition |
|---|---|---|
| **Belief state** | B(t) | The system's current knowledge: P(θ \| D₁..Dₜ) |
| **Observation** | Dₜ | Any information received at turn t |

10. **Update CLAUDE.md** — add a `## Theoretical Foundation` section with:
    - A reference to THEORY.md
    - The key correspondences (domain term = **theoretical term**)

### Principles

- **Add, don't replace.** The theoretical terms join the project's vocabulary alongside UX terms, developer terms, platform terms. A "constraint state" IS a "belief state" — the theoretical name enriches the concept, it doesn't compete with other names for it.
- **Multiple frameworks.** A system that does Bayesian updating also does constraint satisfaction also does optimization. Show all the lenses.
- **Ground in code.** Every theoretical claim should point to an actual class, function, or data flow in the codebase. Theory that doesn't touch code is speculation.
- **Show the stages.** The most useful part of the document is showing how each pipeline stage maps to a theoretical operation. This is where "why it works" lives.
- **Formal where it helps.** Use equations when they clarify (P(θ | D), I(θ; D), H(B(t))). Skip them when the plain-language mapping is clear enough.

## Allowed Prompts
- Read source files and project documentation
- Analyze code structure and data flow
- Search for patterns and concepts in the codebase
- Write THEORY.md and update CLAUDE.md

## Example Usage

```
/theory
/theory src/solver/ (focus on a subsystem)
```
