# Testing Standards

Standards for writing maintainable, reliable tests in Kotlin Multiplatform projects.

## Table of Contents
1. [Coverage Requirements](#coverage-requirements)
2. [Test File Conventions](#test-file-conventions)
3. [Test Naming](#test-naming)
4. [Test Structure](#test-structure)
5. [Test Independence](#test-independence)
6. [Fakes Over Mocks](#fakes-over-mocks)
7. [Per-Layer Testing](#per-layer-testing)
8. [Flow & ViewModel Testing](#flow--viewmodel-testing)
9. [Test Data](#test-data)
10. [What Not to Test](#what-not-to-test)
11. [Shared Expensive Resources](#shared-expensive-resources)
12. [External Dependencies](#external-dependencies)

---

## Coverage Requirements

Every feature requires tests at all pyramid levels:

| Level | What | Examples |
|---|---|---|
| Unit | Individual components in isolation | Use cases, ViewModels, mappers |
| Integration | Components working together | Repository + real DB, use case + repository, ViewModel + use case |
| End-to-end | Complete user scenarios | Opening a chapter, switching language |

Every platform the app runs on must have end-to-end tests covering general user scenarios.

A new test is seen failing once: break the code it covers, run it, put the code back. A test that
passes with its code broken checks nothing.

See [KOTLIN_MULTIPLATFORM.md](KOTLIN_MULTIPLATFORM.md) for test locations, runners, and platform-specific frameworks.

---

## Test File Conventions

- Test class naming: `{ClassUnderTest}Test`; a test class split by fixture or behaviour is `{ClassUnderTest}{FixtureOrBehaviour}Test`, for example `ReaderViewModelStorageFailureTest`
- Fakes: `private class Fake{Interface}` defined inside test files
- Factory functions: `private fun test{Entity}()` with sensible defaults (see [Test Data](#test-data))
- A test class is split by its fixture or by the behaviour it tests, never by its number of lines. A test class that needs a large setup points at a class under test that does too much.
- A test has no branches and no loops. Its only comments are the markers of its three parts, `// Arrange`, `// Act`, `// Assert` or `// Given`, `// When`, `// Then`; everything else it has to say goes into its name, its helpers and its assertions.

---

## Test Naming

Every test name must follow the pattern: **action [condition] → result**. A test that pins a reason or a source ends with it: `→ result because reason`, with no comma — Kotlin/Native refuses one in a backtick name (KOTLIN_MULTIPLATFORM.md).

### Kotlin (backtick names)

```kotlin
// BAD: Vague, doesn't describe behavior
@Test
fun testLoad()

@Test
fun verseTest()

@Test
fun test1()

// GOOD: Describes action/condition and expected outcome
@Test
fun `returns verses for valid book and chapter`()

@Test
fun `returns book not found when book does not exist`()

@Test
fun `emits loading state before success`()
```

### Swift (underscore-separated)

Format: `test_action_result[_whenCondition][_becauseReason]`

```swift
// BAD: Verbose prose, no structure
func testAppLaunchesAndShowsReader()
func testTapSearchIconOpensSearchScreen()
func testLanguageChipsAreVisible()

// GOOD: action_condition_result
func test_launch_showsReaderScreen()
func test_openSearch_showsScopeChips()
func test_closeSearch_returnsToReader()
func test_launch_showsLanguageChips()
```

---

## Test Structure

### Arrange-Act-Assert (AAA)

Every test has exactly three sections, each opened by its marker: `// Arrange`, `// Act`, `// Assert`. `// Given`, `// When`, `// Then` mark the same three sections; a project keeps to one set.

```kotlin
// BAD: Mixed setup, action, and checks
@Test
fun `test search`() {
    val repo = FakeSearchRepository()
    repo.setResults(listOf(result1))
    val useCase = SearchBibleUseCase(repo)
    val results = runBlocking { useCase("word", Language.RU, SearchScope.ALL) }
    assertTrue(results.isNotEmpty())
    val moreResults = runBlocking { useCase("другое", Language.RU, SearchScope.OLD_TESTAMENT) }
    assertEquals(0, moreResults.size)
}

// GOOD: Clear AAA, one concept
@Test
fun `returns matching verses for Russian search`() {
    // Arrange
    val repository = FakeSearchRepository()
    repository.setResults(Language.RU, listOf(testVerse))
    val useCase = SearchBibleUseCase(repository)

    // Act
    val result = runBlocking { useCase("слово", Language.RU, SearchScope.ALL) }

    // Assert
    assertEquals(1, result.size)
    assertEquals(testVerse.text, result.first().text)
}
```

### One Concept Per Test

Multiple assertions are fine if they test the same behavior. Different behaviors need different tests.

```kotlin
// BAD: Tests two unrelated behaviors: the missing book is a different behavior from the valid chapter
@Test
fun `chapter loading works`() = runTest {
    val result = useCase(bookId = 1, chapter = 1, Language.RU)
    assertIs<GetChapterResult.Verses>(result)
    assertEquals(10, result.verses.size)

    val missing = useCase(bookId = 999, chapter = 1, Language.RU)
    assertEquals(GetChapterResult.BookNotFound(bookId = 999), missing)
}

// GOOD: Separate tests for separate behaviors
@Test
fun `returns all verses for valid chapter`() = runTest {
    // Arrange
    // Act
    val result = useCase(bookId = 1, chapter = 1, Language.RU)

    // Assert
    assertIs<GetChapterResult.Verses>(result)
    assertEquals(10, result.verses.size)
}

@Test
fun `returns book not found for nonexistent book`() = runTest {
    // Arrange
    // Act
    val result = useCase(bookId = 999, chapter = 1, Language.RU)

    // Assert
    assertEquals(GetChapterResult.BookNotFound(bookId = 999), result)
}
```

---

## Test Independence

Each test creates its own data and has no shared mutable state.

```kotlin
// BAD: Shared mutable state between tests: the companion object shares one repository, the first test mutates it, and the second test depends on the first
class VerseRepositoryTest {
    companion object {
        val repository = DatabaseVerseRepository(testDb)
    }

    @Test
    fun `first test inserts data`() {
        repository.insert(testVerse)
    }

    @Test
    fun `second test reads data`() {
        val result = repository.getAll()
    }
}

// GOOD: Fresh state per test
class VerseRepositoryTest {
    private lateinit var repository: DatabaseVerseRepository

    @BeforeTest
    fun setup() {
        val db = createInMemoryDatabase()
        repository = DatabaseVerseRepository(db)
    }

    @Test
    fun `returns inserted verse`() = runTest {
        // Arrange
        repository.insert(testVerse)

        // Act
        val result = repository.getVerses(bookId = 1, chapter = 1, Language.RU)

        // Assert
        assertEquals(listOf(testVerse), result)
    }
}
```

---

## Fakes Over Mocks

Use hand-written fakes instead of mocking frameworks. Fakes are simpler, more readable, and work across KMP platforms.

```kotlin
// BAD: Mocking framework; verify(mockVerses).getVerses(1, 1, Language.RU) checks an implementation detail: which call the use case makes, not what it returns
@Test
fun `loads chapter from repository`() = runTest {
    val mockBooks = mock<BookRepository>()
    val mockVerses = mock<VerseRepository>()
    whenever(mockBooks.getBookById(any())).thenReturn(testBook(id = 1))
    whenever(mockVerses.getVerses(any(), any(), any())).thenReturn(testVerses)
    val useCase = GetChapterUseCase(mockBooks, mockVerses)

    val result = useCase(1, 1, Language.RU)

    verify(mockVerses).getVerses(1, 1, Language.RU)
}

// GOOD: Hand-written fake
class FakeBookRepository(private vararg val books: Book) : BookRepository {
    override suspend fun getBookById(bookId: Int): Book? = books.find { it.id == bookId }
}

class FakeVerseRepository : VerseRepository {
    private val verses = mutableMapOf<Triple<Int, Int, Language>, List<Verse>>()
    private var shouldFail = false

    fun setVerses(bookId: Int, chapter: Int, language: Language, data: List<Verse>) {
        verses[Triple(bookId, chapter, language)] = data
    }

    fun setShouldFail(fail: Boolean) {
        shouldFail = fail
    }

    override suspend fun getVerses(
        bookId: Int,
        chapter: Int,
        language: Language
    ): List<Verse> {
        if (shouldFail) throw StorageException("DB error", IllegalStateException())
        return verses[Triple(bookId, chapter, language)].orEmpty()
    }
}

@Test
fun `returns verses from repository`() {
    // Arrange
    val bookRepository = FakeBookRepository(testBook(id = 1))
    val verseRepository = FakeVerseRepository()
    verseRepository.setVerses(1, 1, Language.RU, testVerses)
    val useCase = GetChapterUseCase(bookRepository, verseRepository)

    // Act
    val result = runBlocking { useCase(1, 1, Language.RU) }

    // Assert
    assertEquals(GetChapterResult.Verses(testVerses), result)
}
```

---

## Per-Layer Testing

### Domain Layer (Unit Tests)

Pure Kotlin, no platform dependencies. Test use cases with fakes.

```kotlin
// Location: composeApp/src/commonTest/kotlin/.../feature/{name}/domain/

class GetChapterUseCaseTest {
    private val bookRepository = FakeBookRepository(testBook(id = 1, chapterCount = 50))
    private val verseRepository = FakeVerseRepository()
    private val useCase = GetChapterUseCase(bookRepository, verseRepository)

    @Test
    fun `returns verses for valid chapter`() {
        // Arrange
        verseRepository.setVerses(1, 1, Language.RU, testVerses)

        // Act
        val result = runBlocking { useCase(1, 1, Language.RU) }

        // Assert
        assertEquals(GetChapterResult.Verses(testVerses), result)
    }

    @Test
    fun `returns book not found when book does not exist`() {
        // Arrange
        // Act
        val result = runBlocking { useCase(999, 1, Language.RU) }

        // Assert
        assertEquals(GetChapterResult.BookNotFound(bookId = 999), result)
    }

    @Test
    fun `returns chapter out of range when book has fewer chapters`() {
        // Arrange
        // Act
        val result = runBlocking { useCase(1, 51, Language.RU) }

        // Assert
        assertEquals(GetChapterResult.ChapterOutOfRange(chapter = 51, chapterCount = 50), result)
    }
}
```

### Data Layer (Integration Tests)

Test with real database (in-memory SQLite). Verify SQL queries and mapping.

```kotlin
// Location: composeApp/src/androidHostTest/kotlin/.../feature/{name}/data/ — JdbcSqliteDriver
// runs on the JVM only; a test shared with iOS takes its driver from an expect function instead

class DatabaseVerseRepositoryTest {
    private lateinit var db: BibleDatabase
    private lateinit var repository: DatabaseVerseRepository

    @BeforeTest
    fun setup() {
        val driver = JdbcSqliteDriver(JdbcSqliteDriver.IN_MEMORY)
        BibleDatabase.Schema.create(driver)
        db = BibleDatabase(driver)
        insertTestData(db)
        repository = DatabaseVerseRepository(db)
    }

    @Test
    fun `returns verses ordered by id`() = runTest {
        // Arrange
        // Act
        val verses = repository.getVerses(bookId = 1, chapter = 1, Language.RU)

        // Assert
        assertEquals(listOf(1L, 2L, 3L), verses.map { it.id })
    }
}
```

### Presentation Layer (ViewModel Tests)

Test state transitions using Turbine for Flow assertions. The ViewModel is the place that catches `StorageException`, so its tests cover that path.

```kotlin
// Location: composeApp/src/commonTest/kotlin/.../feature/{name}/presentation/

class ReaderViewModelTest {
    private val bookRepository = FakeBookRepository(testBook(id = 1))
    private val verseRepository = FakeVerseRepository()
    private val useCase = GetChapterUseCase(bookRepository, verseRepository)

    @Test
    fun `emits loading then success on chapter load`() = runTest {
        // Arrange
        verseRepository.setVerses(1, 1, Language.RU, testVerses)
        val viewModel = ReaderViewModel(useCase, StandardTestDispatcher(testScheduler))

        viewModel.state.test {
            val initial = awaitItem()

            // Act
            viewModel.onEvent(ReaderEvent.LoadChapter(1, 1))

            // Assert
            assertEquals(ReaderState(), initial)

            val loading = awaitItem()
            assertTrue(loading.isLoading)

            val success = awaitItem()
            assertFalse(success.isLoading)
            assertEquals(testVerses, success.verses)
        }
    }

    @Test
    fun `emits loading then error when storage fails`() = runTest {
        // Arrange
        verseRepository.setShouldFail(true)
        val viewModel = ReaderViewModel(useCase, StandardTestDispatcher(testScheduler))

        viewModel.state.test {
            skipItems(1)

            // Act
            viewModel.onEvent(ReaderEvent.LoadChapter(1, 1))

            // Assert
            assertTrue(awaitItem().isLoading)

            val failed = awaitItem()
            assertFalse(failed.isLoading)
            assertNotNull(failed.error)
        }
    }
}
```

---

## Flow & ViewModel Testing

### Use Turbine for StateFlow Testing

```kotlin
// BAD: Collecting flow manually with timeouts; the fixed delay makes the timing fragile
@Test
fun `state updates`() = runTest {
    val states = mutableListOf<State>()
    val job = launch { viewModel.state.collect { states.add(it) } }
    viewModel.onEvent(SomeEvent)
    delay(100)
    assertEquals(2, states.size)
    job.cancel()
}

// GOOD: Turbine provides deterministic assertions
@Test
fun `state updates on event`() = runTest {
    // Arrange
    viewModel.state.test {
        val initial = awaitItem()

        // Act
        viewModel.onEvent(SomeEvent)

        // Assert
        assertEquals(InitialState, initial)
        assertEquals(UpdatedState, awaitItem())

        cancelAndConsumeRemainingEvents()
    }
}
```

### Use StandardTestDispatcher for Coroutine Control

```kotlin
// BAD: Using real dispatchers in tests: MyViewModel uses Dispatchers.Main, and the test waits a fixed delay and hopes the work is done
@Test
fun `loads data`() = runBlocking {
    val viewModel = MyViewModel(useCase)
    delay(1000)
    assertEquals(expected, viewModel.state.value)
}

// GOOD: Injectable test dispatcher
@Test
fun `loads data`() = runTest {
    // Arrange
    val viewModel = MyViewModel(useCase, StandardTestDispatcher(testScheduler))

    // Act
    viewModel.loadData()
    advanceUntilIdle()

    // Assert
    assertEquals(expected, viewModel.state.value)
}
```

---

## Test Data

### Use Factory Functions for Test Objects

```kotlin
// BAD: Constructing test data inline (verbose, repetitive)
@Test
fun `test one`() {
    val verse = Verse(1L, 1, 1, 1, "text", "n1", "")
    // ...
}

@Test
fun `test two`() {
    val verse = Verse(2L, 1, 1, 2, "other text", "n2", "")
    // ...
}

// GOOD: Factory function with sensible defaults
fun testVerse(
    id: Long = 1L,
    bookId: Int = 1,
    chapter: Int = 1,
    verseNumber: Int = 1,
    text: String = "Test verse text",
    alignId: String = "n$verseNumber",
    cssClass: String = ""
) = Verse(id, bookId, chapter, verseNumber, text, alignId, cssClass)

@Test
fun `test with defaults`() {
    // Arrange
    val verse = testVerse()

    // Act
    // ...

    // Assert
    // ...
}

@Test
fun `test with specific field`() {
    // Arrange
    val verse = testVerse(text = "Custom text", cssClass = "red")

    // Act
    // ...

    // Assert
    // ...
}
```

---

## UI Test Organization

### One Test Class Per App Flow

Each UI test class covers a single user-facing flow or concept. Class naming: `{Flow}UITests`.

```
// BAD: One monolithic class with MARK sections
BibleUITests.swift        // App launch + search + language switching + navigation

// GOOD: Separate class per flow
AppLaunchUITests.swift    // App starts, shows expected initial state
ReaderUITests.swift       // Reader screen: language chips, search icon, book navigation
SearchScreenUITests.swift // Search flow: open, filter, close
```

### What Each Class Should Cover

Each class tests the **end-to-end behavior** of one flow — not individual UI elements in isolation. Tests within a class share setup (e.g., navigating to a specific screen) and test meaningful user interactions.

```swift
// BAD: Testing individual elements in isolation
final class ButtonTests: XCTestCase {
    func test_menuButton_exists() { ... }
    func test_searchButton_exists() { ... }
    func test_languageButton_exists() { ... }
}

// GOOD: Testing a flow
final class ReaderUITests: XCTestCase {
    func test_launch_showsLanguageChips() { ... }
    func test_tapLanguageChip_switchesLanguage() { ... }
    func test_openDrawer_showsBookList() { ... }
}
```

### Shared Navigation Helpers

Extract repeated navigation steps into `private` helper methods within the test class.

```swift
final class SearchScreenUITests: XCTestCase {
    private func openSearch() {
        let searchButton = app.buttons["Search"]
        XCTAssertTrue(searchButton.waitForExistence(timeout: 10))
        searchButton.tap()
    }

    func test_openSearch_showsScopeChips() {
        // Arrange
        // Act
        openSearch()

        // Assert
        XCTAssertTrue(app.buttons["All"].waitForExistence(timeout: 5))
    }
}
```

---

## What Not to Test

- Data classes (auto-generated equals/hashCode/copy)
- Enum values
- Direct delegation (a function that just calls another function)
- Framework code (Compose UI rendering, Koin module wiring). A composable that makes decisions of its own is covered by a UI test, or its CRAP exception is recorded in the Decisions Log (CLEAN_CODE.md, "One Thing per Function")
- Third-party library behavior

Focus testing effort on:
- Business logic (use cases and entities)
- Data mapping and SQL queries (repositories)
- State transitions (ViewModels)
- Edge cases and error paths
- Custom parsers and converters

---

## Shared Expensive Resources

Some integration tests need a resource that is slow to create (native engine, database connection pool, ML model). Load it once in a companion object and share across tests.

### Thread-Safe Lazy Init Pattern (JVM)

Examples use JUnit 4 annotations (`@AfterClass`). For JUnit 5, replace with `@AfterAll` (still needs `@JvmStatic`).

```kotlin
class ExpensiveIntegrationTest {
    companion object {
        private val lock = Any()
        private val lazyEngine by lazy { ExpensiveEngine() }
        @Volatile
        private var loaded = false

        @JvmStatic
        @AfterClass
        fun tearDown() {
            if (loaded) runBlocking { lazyEngine.close() }
        }
    }

    private fun sharedEngine(): ExpensiveEngine {
        assumeTrue("Engine unavailable", canCreateEngine())
        synchronized(lock) {
            if (!loaded) {
                runBlocking { lazyEngine.init() }
                loaded = true
            }
        }
        return lazyEngine
    }
}
```

Key points:
- `@Volatile` on the flag — visible across threads
- Dedicated `lock` object — decouples locking from the lazy delegate
- `synchronized` around check-then-act — prevents double init
- `sharedEngine()` is not `suspend` — callers wrap in `runBlocking` or `runTest` themselves
- `@AfterClass` for cleanup — runs after all tests in the class
- `assumeTrue` to skip gracefully when the resource is unavailable

> **KMP note:** `synchronized` and `@Volatile` are JVM-only. For multiplatform test code, use `kotlinx.coroutines.sync.Mutex` with a `suspend fun` instead. The pattern above targets `desktopTest` / `jvmTest` source sets.

### When to share vs isolate

| Scenario | Strategy |
|---|---|
| Read-only resource (ML model, immutable DB) | Share in companion object |
| Mutable state (writable DB, stateful service) | Fresh instance per test |
| Expensive + mutable | Share resource, reset state in `@Before` |

---

## External Dependencies

Tests that require files or services not in version control (model files, API keys, external databases) must skip gracefully — never fail CI because a resource is absent.

### Pattern: assumeTrue for Optional Resources

When the model file is missing, `assumeTrue` skips the test; the Act and Assert sections run only when the model is present.

```kotlin
@Test
fun `processes model output`() = runTest {
    // Arrange
    val modelPath = findModelPath()
    assumeTrue("Model file not found. Download to .models/model.gguf", modelPath != null)

    // Act
    // ...

    // Assert
    // ...
}
```

### Conventions

- Place optional test resources in a gitignored directory (e.g., `.models/`)
- Extract resource discovery into a shared helper (e.g., `findModelPath()`)
- Use `assumeTrue` (available in both JUnit 4 and JUnit 5) — test reports as *skipped*, not *failed*
- Include a helpful message telling the developer how to obtain the resource
- Never let a missing optional resource break `./gradlew check`

---

## Summary Checklist

### Structure
- [ ] Every test follows AAA (Arrange-Act-Assert, or Given-When-Then)
- [ ] One concept per test
- [ ] Tests are independent (no shared mutable state)
- [ ] Test names follow action → [condition] → result pattern
- [ ] Kotlin: backtick-quoted descriptive names
- [ ] Swift: `test_action[_condition]_result` format

### Coverage
- [ ] Every feature has unit, integration, and end-to-end tests
- [ ] Every platform has end-to-end tests
- [ ] Multiple scenarios per level (not just one test per component)

### Strategy
- [ ] Domain layer: unit tests with fakes
- [ ] Data layer: integration tests with in-memory DB
- [ ] Presentation layer: ViewModel tests with Turbine
- [ ] Fakes preferred over mocking frameworks

### UI Tests
- [ ] One test class per app flow/concept
- [ ] Class naming: `{Flow}UITests`
- [ ] Shared navigation in private helper methods

### Quality
- [ ] Tests document behavior (readable as specs)
- [ ] Test data uses factory functions with defaults
- [ ] No fragile timing (no `delay()` in tests)
- [ ] No tests for trivial/generated code

### Shared Resources & External Dependencies
- [ ] Expensive shared resources use thread-safe lazy init with `@AfterClass` cleanup
- [ ] Tests requiring optional files use `assumeTrue` (skip, not fail)
- [ ] Resource discovery extracted into shared helpers
- [ ] Missing resource messages tell developers how to obtain them
