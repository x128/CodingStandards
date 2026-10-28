# Test cases

Every case of the product, grouped by feature. Each says what the user does and sees, and how it
is covered: `manual` — `/qa` walks it by hand — or `e2e: <test>` — an end-to-end test runs it
after every task. A full regression takes every case.

## Library

- **TC-001 Opening an item.** Touch any item in a list: its content appears at once, with no grey
  screen and spinner before it. — manual
  - Got past `/qa`: has the defect in `<commit>`, fixed in `<commit>`; the check read a screenshot
    after the screen opened, not the frames between the touch and the content.
- **TC-002 Empty folder.** Open an empty folder: the empty state is shown. — e2e:
  `FileListE2ETest.emptyFolder`
