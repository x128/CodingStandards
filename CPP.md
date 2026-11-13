# C++ Coding Standards

> What is particular to C++ in a product whose core is written in C++ and whose apps are native:
> Swift on iOS, Kotlin on Android, or others. What holds in every language stays in CLEAN_CODE.md,
> ARCHITECTURE.md and TESTING.md; this file only adds to them.

---

## Decisions of the Code Owner

C++ leaves open choices that the other standards settle for Kotlin and Swift. The code owner of each
project makes them once, before the C++ code they govern is written.

An agent that reads this file in a project — when it writes the project's AGENTS.md, or when a task
first touches C++ code — reads the requirements, section "How the code is made". For each decision
below that is not answered there, it asks the code owner the question as written here, and writes
the answer there as one line. No C++ code that a decision governs is written while it is open.

The text of a question is copied, not written again: as it is for a code owner who writes in
English, translated sentence by sentence for another language, keeping C++, Swift, Kotlin,
std::expected, RAII and the names of projects in English. With only one of Swift and Kotlin, the
other is left out of the text; with neither, "Swift and Kotlin" becomes the code that calls the
core.

### How the C++ core reports a failure

> Now about failures in the C++ part of the app. An outcome the requirements name, such as "book not
> found", is settled already: it is returned as a value. Bugs are a question of their own. This one
> is about the rest: the disk, the database or the network failing. C++ has two ways to report such
> a failure, and large codebases have gone each way. The creator of C++ and the C++ Core Guidelines
> recommend exceptions: a failure cannot be dropped silently, and it passes up on its own. Google,
> Chromium and LLVM return failures as values: Google because its old code was written without
> exceptions, LLVM to keep its compiled code small; what they gain is that every place a failure
> passes is visible in the code. The choice concerns only the C++ code: either way, the core hands a
> failure to Swift and Kotlin as their own exception (a Swift Error, a Kotlin exception), and their
> code is the same. Speed does not decide it: these failures are rare, and the disk or the network
> is far slower than either way. Changing the choice later is costly. Which way does the core report
> these failures?

- *The core throws exceptions*: a failure is thrown and passes on its own through the code in
  between, up to the function that Swift or Kotlin called, which must catch it and hand it over: a
  catch missing there ends the app. The code in between has no failure checks and stays short, but
  any call in it may be where a failure leaves, unseen in the code: objects that clean up after
  themselves (RAII) release what was taken, and each step leaves the data valid. Code that returns
  error values needs the same care, but there each exit is visible. Turning exception support on in
  code that did not use it has been reported to grow its compiled code by 15–38%, mostly in Windows
  code; the checks that error values need add code too, and how the two compare on iOS or Android is
  not known. Such a core cannot be reused in code built without exceptions, as in Chromium and in
  many games and embedded systems.
- *The core returns error values*: every function that can fail says so in its return type
  (std::expected), and every caller checks the failure and passes it on by hand. The code is longer,
  but every place a failure passes is visible. The build can be set to stop a caller that ignores a
  failure, but not one that reads the value without checking it. That is found only while the app
  runs, and not always: one way of reading stops the app, the other, unless extra checks are
  switched on in the build, may give a wrong value or corrupt memory. The core can also be reused in
  code built without exceptions, if the libraries it uses do not throw either.

The line in the requirements: `- How the C++ core reports a failure: [the answer]`

### What a bug in the C++ code does

> Now about bugs in the C++ part of the app. A bug is a mistake in the code itself: a function is
> called with arguments its rules forbid, or the code finds its own data in a state that should be
> impossible. The code checks for such states where it matters; the question is what happens when a
> check finds one. An exception from C++ cannot pass into Swift or Kotlin on its own: if one reaches
> Swift, the app ends, and on Android it must not cross into Kotlin at all. So the C++ code itself
> decides what a bug does; in the Swift and Kotlin code of the app, a bug stops the app. The C++
> sources split. The C++ Core Guidelines stop the program by default, and so does Herb Sutter in a
> proposal of 2018. Bjarne Stroustrup would rather a library report a broken rule to its caller, and
> leaves the choice to whoever builds the whole system. Many projects, LLVM among them, run most
> checks only in development builds and keep a few on in the shipped app. Projects often mix: cheap
> checks stop the app, costly ones run only while developing. What happens when a check finds a bug?

- *The app stops at once*: the check stays in the shipped app; when it fails, the app writes what it
  found to the log and ends; the Swift and Kotlin code also ends the app on a bug. Work not yet
  saved is lost, and the crash report points to the place. The app goes no further with broken data,
  but whatever the bug saved before the check stays wrong.
- *The operation fails, the app goes on*: the check reports the bug the way the core reports a
  failure of the disk or the network, and Swift or Kotlin shows a general error. Every function that
  checks becomes one that can fail and says so, and a check in a function that must not fail, such
  as one that cleans up, still ends the app. The user keeps working, but the data the bug touched
  may already be wrong, and a bug that keeps happening is easy to miss.
- *The checks run only while developing*: development and test builds check and stop; the shipped
  app leaves the checks out, as release builds usually do with the standard assert. The shipped app
  is a little smaller and faster, but there a bug goes on unchecked, and what follows cannot be
  known.

The line in the requirements: `- What a bug in the C++ code does: [the answer]`
