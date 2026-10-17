# Evaluation

The state of the work that improves these standards by evidence
([skills/self-improve.md](skills/self-improve.md)). This file is rewritten after each iteration;
git keeps its history. It is never copied into a project that is being measured.

## Decisions of the human in force

| Topic | Decision | Where it is in the standards |
|---|---|---|
| Use case | Holds the application-specific business rules of one operation: input, output, the steps between them with their checks and decisions (Martin, Clean Architecture ch. 20 p. 192, ch. 22 p. 204). Not one per user action. Rules true of an entity whatever the operation live in the entity | ARCHITECTURE.md, "Use Cases" |
| Principles and forms | Principles are separate from their implementation; the same use case can be written as a class, a function, a `Flow` or `Publisher`, a state machine; code under the standard uses the class | ARCHITECTURE.md, "Use Cases" |
| Outcomes | Each use case returns its own sealed type when its requirements name more than one outcome; no `kotlin.Result` for outcomes; no error type shared by a feature; a repository answers "none" with `null` | ARCHITECTURE.md, KOTLIN.md |
| Failures nobody names | Storage, network and platform failures are thrown as `StorageException` (`StorageError` in Swift); a library's own exceptions are caught only in one function, `storageCall`; the side that starts operations catches through one function | ARCHITECTURE.md, KOTLIN.md, SWIFT.md; CLEAN_CODE.md, "Report a Failure by Its Kind" |
| Shared refusal | A refusal that an entity rule gives is declared with that rule; each use case carries it in one case of its own type | ARCHITECTURE.md |
| Nothing to check or decide | The project chooses (a) no use case, or (b) a use case of one call, and records it as D-002 | PLANNING_GUIDE.md |
| Dependency inversion | A given | ARCHITECTURE.md |
| Comments | None by default; a reason, a warning, a unit, an outside source or a promise becomes a name, a type or a check in the code where its reader looks, pinned by a test; the number of a rule of the requirements goes into the test name; where there is no comment, a reason that only a test name or the plan gives gets a name too and a review reports it; work to do goes to the tracker, history to the commit message (17 Oct: measured on two applications in refactoring; no gain seen when a project is built from scratch); a comment is never just deleted; a project may allow kinds of comments as D-003; every test marks its three parts with `// Arrange`, `// Act`, `// Assert` or `// Given`, `// When`, `// Then` | CLEAN_CODE.md, KOTLIN.md, TESTING.md |
| Size | No limits in lines; a function does one thing and has a CRAP score of 8 or below, exceptions recorded; a flat list of checks in the order of the rules may stay whole with its exception and is not wrapped in a helper type to lower the score (trial since 17 Oct, iteration 4); a test class is split by fixture or behaviour | CLEAN_CODE.md, KOTLIN.md, TESTING.md |
| Prototypes | Follow the same standards | PLANNING_GUIDE.md, "Prototype tasks" |
| Editing | Shorten rather than add; fix obvious defects without asking; the human sets the direction and confirms the cost of any run above 1 million tokens | skills/self-improve.md, steps 2 to 4 |

## What the evidence says now

Up to iteration 4 it comes from one application, Tripsplit (`templates/self-improve/example/`): shared
expenses of a trip, Kotlin on the JVM, about 2 500 lines of main code. Five projects were built on
13–14 Oct 2026 (p1 and p3 under the standards of August 2026; p2, p4, p5 under the new ones), then
refactored in rounds; a sixth, p6, was built from scratch under the current standards on 16 Oct.
The rules changed because of these measurements are trials until a second, different application
confirms them. The projects and raw results are not in this repository; what follows is enough to go on.

**Behaviour.** 25 of 25 acceptance scenarios in p2–p5, at the start and after the last round each
went through; p1 24 and one partly from the start (the id of a deleted trip stays in the settings); p6 24 and one partly (reminder rows of
a deleted trip stay in storage).

**Where the rules are.** In all five first builds the business rules of `RULES.md` are decided in
domain code, except deleting a trip with all it holds (R33), which is in data code in all five; no
difference between the old and the new standards. Rules inside entities: 4–8 under the new
standards against 1–2 under the old.

**Result types and refusals** (trial). "Its own result type for each use case" made p2 and p5 copy
one status check into five use cases, and judges preferred the old standards on "each rule in one
place" in 5 of 6 pairs. After adding "a refusal is declared with its rule", one refactoring round
took the copies from 10 to 0 (p2), 7 to 0 (p5) and 1 to 0 (p4); p6, built with the rule, has none.
The new standards won 5 of 6 blind pairs overall after the first build (confidence 57–70): no
`Impl`, own result types instead of `Result` with error classes, less KDoc.

**Size** (trial). A limit of 200 lines per class made p1 split 31 test classes into 134 (test code
16.1 → 25.1 thousand lines). It was replaced by the CRAP score; after round 3 no function of any
project is above 8, with one or two recorded exceptions each.

**Comments.** Round 3 removed every comment from p1–p5; p6 was written without them. Of 905
removed blocks traced (all 788 of p2, p4, p5 and a sample of 117 of p1, p3), none is lost and 14
are partly lost. The meaning went (p2, p4, p5) into names in the code 327 times, test names 271,
the plan or the tracker 138; 31 only repeated the code. Ten blind judges, before against after
round 3: 9 prefer before (confidence 60–78), 1 after (57); readability before in all 10; tests
after in 7; "each rule in one place" after in 5, equal in 2, before in 3. What they miss after:
reasons, warnings, units and promises of functions, now in tests and in the plan instead of next
to the code; flat lists of checks split into generic wrappers to reach CRAP 8. The changes of
`CHANGES.md` were not run on round 3, so "easy to change" is not measured yet.

**Iteration 1, 17 Oct: "a reason goes into a name in the main code, a test pins it" — untested,
reverted.** The rule was changed (text kept in the work folder as `iter1/standards-B-final`) and one
refactoring round ran on p2, p4, p5 from the state after round 3. Against round 3 the new version
won 6 of 6 judges, but a control round under the old rule (round 4) tied with it 3 to 3: the gain
came from one more round, not from the rule. Against round 2 (with comments) round 2 still won
readability 6 of 6. Nothing got worse: 25 of 25 scenarios, lint clean, no status-check copies, and
the changes of `CHANGES.md` touched the same files on both versions with the same failing
scenario tests. Cause: no reviewer item reached the rule. The code after round 3 has no comments,
so the rule, which speaks of comments, had nothing to act on, and the reviewer neither looks for
reasons kept only in tests and the plan nor reads the plan. The rule locator counts each use of
one message constant as a copy, so its numbers for R32 are not copies.

**Iteration 2, 17 Oct: the same rule where comments still exist — kept as a trial.** One round on
p2, p4, p5 from round 2 (with comments) under the changed rule, against round 3 (one round from the
same start under the old rule). The reviewers' lists cited the changed lines. Of the 386 comments
of the main code that both rounds removed, the meaning landed in the main code in 199 (52%) against
60 (16%) in round 3; only in documents 3 against 52; partly lost 2 against 7; lost 0 in both
(same blocks, same checker prompt). Blind judges: against round 3 the new round won 6 of 6
(60–76), readability 4 of 6; with the KDoc it kept stripped out it still won 6 of 6, readability
5 of 6, so the names carry the gain. Against round 2 (with comments) round 2 still won 6 of 6 on
readability. Nothing got worse: 25 of 25 scenarios (two test sets adapted below the screens, no
check changed), lint clean, no status-check copies. All three projects chose D-003 (b) and kept
KDoc on what the host uses (26, 41 and 19 lines); round 3 had chosen (a).

**Iteration 3, 17 Oct: the same rule for code that has no comments — kept as a trial.** CLEAN_CODE.md
"Comments" gained "Where there is no comment, the same holds" and skills/review.md the matching
check. One round on p2, p4, p5 from round 3, against round 4 (one round from the same start under
the old rule, the same prompts). The reviewers' lists put the new paragraph first. Of 174 reasons
that round 3 had left only in tests or documents (every second one), round 4 moved 5 into the main
code and this round 27 (+1 partly). Blind judges: 3 to 3 against round 4, readability 3 to 3;
"each rule in one place" went to round 4 in 5 of 6, because the reviewers spent their lists on
names instead of on one-place items; the rule locator found no new copies. Judges like names that
state a promise (`deleteIfPresent`, `addOrReplace`) and dislike names that are sentences
(`lowercaseWholeTextAsTheOrderDoes`). Against round 2 (with comments) round 2 still won readability
6 of 6. Nothing got worse: 25 of 25 scenarios, lint clean, no KDoc kept this time.

**Iteration 4, 17 Oct: flat lists of checks and CRAP — kept as a trial.** The CRAP paragraph of
CLEAN_CODE.md names "a flat list of checks in the order of the rules, each returning its refusal"
as a function that may stay above 8, and forbids wrapping it in a helper type only to lower the
score; the smell "Long Function" and the checklists now allow a recorded exception. Tested on the
standards of round 3 plus only this change, from round 2, against round 3. Of the 16 functions
above CRAP 8 in round 2, round 3 moved 3 into new helper types (among them both flat lists:
`FormCheck<T>` in p4, `DraftPartCheck<T>` in p5), this round 1 (not a flat list); the flat lists
stayed whole, two with a recorded exception. Blind judges 3 to 3; "each rule in one place" went
to this round in 5 of 6, the tests to round 3 in 4 of 6. Nothing got worse: 25 of 25 scenarios,
lint clean.

**Iterations 5 and 6, 17 Oct: a second application.** A spec agent wrote Gearshed, the lending
library of a sports club (6 screens, 36 rules, 25 hidden scenarios, 3 changes), on the same
platform; two independent checks recomputed every number and removed ambiguities before anything
was built. Two projects were built from it: p1 under the standards before the trial rules, p2
under the current ones (6.4 million tokens). Both pass 25 of 25 scenarios and lint. Four blind
judges preferred p2, 4 of 4 (60–72), for keeping each fact once and citing the requirements in
test names. Of 20 reasons that a reader derived from the requirements alone, p1 stated 7 in names
of the main code and p2 4: built from scratch, the comment rule showed no gain. Then iteration 3
was repeated on Gearshed: one refactoring round of p1 under the old rules and one under the
current rules, same start. The current rules named 6 of the 20 reasons in the main code against 4 (the same finder gave the start
7, so this count moves by about 3 on its own and decides nothing),
named the write order that decision D-019 relies on (`putItemAfterItsRecords`,
`deleteItemAfterItsLoans`, each pinned by a test that fails when the order is changed), and won
4 of 4 judges (66–72) on readability and tests. Nothing got worse in either. The flat-list rule of
iteration 4 found nothing to act on in Gearshed: neither project wrapped a flat list of checks in
a helper type to lower the score.

**Refactoring converges.** While the standards stay the same, the reviewers' lists of p2, p4, p5
shrink: 11, 11 and 8 items in round 1, 5 each in round 2. After the standards changed, round 3
listed 11 each, and a fourth round on top of it 5, 6 and 5.

## Costs of runs

| Run | Tokens | Source |
|---|---|---|
| Plan and build one project of about 45 tasks | 3–5 million | 23 million for five projects on 13 Oct; about 3.2 million for p6 |
| One refactoring round, per project | 0.8–2.6 million | 2.4 million for three projects, 4.0 million for five; round 3, estimated from the agents' logs: 2.2 and 2.6 million for p1 and p3, which moved from the old standards |
| Measurement of five projects: 10 testers, 10 rule locators, 6 judges, 10 changes | 9 million | 14 Oct |
| Tracing 788 removed comment blocks, with 6 judges | 6 million | 16 Oct |
| Iteration 1: edit gates, one round of three projects, two changes on each arm, 18 judges | 9.1 million | 17 Oct |
| Iteration 2: reviewers, one round of three projects, tracing 386 comments, 3 rule locators, 18 judges | 10.0 million | 17 Oct |
| Iteration 3: edit gates, reviewers, one round of three projects, tracing 174 reasons on two arms, 3 rule locators, 12 judges | 9.2 million | 17 Oct |
| Iteration 4: edit gates, reviewers, one round of three projects, classifying 16 functions on two arms, 6 judges | 4.9 million | 17 Oct |
| A new application: spec with two checks, two builds of about 45 tasks, measurement (4 testers, 2 locators, 6 changes, 4 judges, a reason list) | 11.4 million | 17 Oct |
| Two refactoring rounds of one project with a reason list and 4 judges | 2.7 million | 17 Oct |

A first estimate has been exceeded by up to 1.6 times.

## Open directions

1. **Reasons next to the code.** Iterations 2 and 3 moved reasons into the main code (16% to 52%
   of comments; 3% to 16% of reasons left in tests). In every comparison the judges still found
   the commented version easier to read (6 of 6 each time); keeping comments goes against the
   human's decision, so it is only reported. Confirmed on a second application in refactoring
   (iteration 6); when a project is built from scratch the rule showed no effect (iteration 5), so
   builders may need the same check that reviewers now have. Open: names that are whole sentences;
   a name could state the fact and leave the reason to the test.
2. **CRAP and flat lists of checks.** Done as a trial in iteration 4 (above). Open: whether the
   same holds for other shapes that agents split only for the score (a map of lambdas in place of
   a four-branch `when` appeared in p4).
3. **The name `storageCall`.** The rule covers "storage, network or platform" libraries, so agents
   catch `RatesException` and `DateTimeParseException` in `storageCall`; judges say the name
   misleads. Needs the human: the name is in the standards.
4. **Copies of field checks.** The rule locator finds the checks of an expense's fields decided in
   two or three places in p2, p4, p5 and p6. Not analysed.
5. **Deleting with everything.** Deleting a trip with all it holds is decided in data code in all
   six projects; p6 forgot one table. Not analysed.
6. **Failures in signatures.** Two judges of p3 prefer failures in the signatures
   (`Result<_, DataError>`) to a thrown `StorageException`. This goes against a decision of the
   human; recorded, not pursued.
7. **Swift.** Every project so far was Kotlin on the JVM; SWIFT.md has never been measured.

## Sources

The books and papers below, and the notes made while reading them, are in the folder
`CodingStandards-Sources`. It is not part of this repository: ask the human where it is. Its
`INDEX.md` lists every file and says, for each book, whether the notes give the printed page or
the page of the PDF.

- **Use cases and layers**: Martin, Clean Architecture; Martin, Agile Software Development; Jacobson
  et al., Object-Oriented Software Engineering, and Use-Case 2.0; Cockburn, Writing Effective Use
  Cases; Evans, Domain-Driven Design; Vernon, Implementing Domain-Driven Design and DDD Distilled;
  Millett and Tune; Fowler, Patterns of Enterprise Application Architecture and UML Distilled;
  van Deursen and Seemann, Dependency Injection; Khorikov, Unit Testing; Larman, Applying UML and
  Patterns; Richardson, Microservices Patterns; Young, CQRS Documents; Freeman and Pryce, GOOS;
  Google, Guide to app architecture.
- **Other paradigms**: Martin, Functional Design; Wlaschin, Domain Modeling Made Functional;
  Chiusano and Bjarnason, Functional Programming in Scala; Granin, Functional Design and
  Architecture; Abelson and Sussman, SICP; Normand, Grokking Simplicity; Harel, Statecharts;
  Armstrong, Programming Erlang; the Elm architecture, TCA, Redux; Combine and Kotlin Flow
  documentation; Martin's blog.
- **Comments and size**: Martin, Clean Code (1st and 2nd editions) and The Clean Coder; Fowler,
  Refactoring; Clausen, Five Lines of Code; Beck, Implementation Patterns and TDD by Example;
  McConnell, Code Complete; Hunt and Thomas, The Pragmatic Programmer; Meszaros, xUnit Test
  Patterns; Koskela, Effective Unit Testing; Savoia and Evans, the CRAP metric and crap4j; Martin's
  crap4java and posts on X; the Ousterhout–Martin discussion; detekt, SwiftLint and ktlint
  documentation.
