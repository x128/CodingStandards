# Testing Standards

Standards for writing maintainable, reliable tests in Kotlin Multiplatform projects.

## Table of Contents
1. [Test Naming](#test-naming)
2. [Test Structure](#test-structure)
3. [Test Independence](#test-independence)
4. [Fakes Over Mocks](#fakes-over-mocks)
5. [Per-Layer Testing](#per-layer-testing)
6. [Flow & ViewModel Testing](#flow--viewmodel-testing)
7. [Test Data](#test-data)
8. [What Not to Test](#what-not-to-test)

---

## Test Naming

Use backtick-quoted descriptive names that document behavior.

```kotlin
// BAD: Vague, doesn't describe behavior
@Test
fun testLoad()

@Test
fun verseTest()

@Test
fun test1()

// GOOD: Describes scenario and expected outcome
@Test
fun `returns verses for valid book and chapter`()

@Test
fun `returns failure when book does not exist`()

@Test
fun `emits loading state before success`()
```

---

## Test Structure

### Arrange-Act-Assert (AAA)

Every test has exactly three sections, separated by blank lines.

```kotlin
// BAD: Mixed setup, action, and checks
@Test
fun `test search`() {
    val repo = FakeSearchRepository()
    repo.setResults(listOf(result1))
    val useCase = SearchBibleUseCase(repo)
    val results = runBlocking { useCase("word", Language.RU, SearchScope.ALL) }
    assertTrue(results.isSuccess)
    val moreResults = runBlocking { useCase("другое", Language.RU, SearchScope.OLD_TESTAMENT) }
    assertEquals(0, moreResults.getOrThrow().size)
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
    assertEquals(1, result.getOrThrow().size)
    assertEquals(testVerse.text, result.getOrThrow().first().text)
}
```

### One Concept Per Test

Multiple assertions are fine if they test the same behavior. Different behaviors need different tests.

```kotlin
// BAD: Tests two unrelated behaviors
@Test
fun `chapter loading works`() {
    val result = useCase(bookId = 1, chapter = 1, Language.RU)
    assertTrue(result.isSuccess)
    assertEquals(10, result.getOrThrow().size)

    val error = useCase(bookId = 999, chapter = 1, Language.RU)
    assertTrue(error.isFailure) // Different behavior!
}

// GOOD: Separate tests for separate behaviors
@Test
fun `returns all verses for valid chapter`() {
    val result = useCase(bookId = 1, chapter = 1, Language.RU)

    assertTrue(result.isSuccess)
    assertEquals(10, result.getOrThrow().size)
}

@Test
fun `returns failure for nonexistent book`() {
    val result = useCase(bookId = 999, chapter = 1, Language.RU)

    assertTrue(result.isFailure)
}
```

---

## Test Independence

Each test creates its own data and has no shared mutable state.

```kotlin
// BAD: Shared mutable state between tests
class VerseRepositoryTest {
    companion object {
        val repository = VerseRepositoryImpl(testDb) // Shared!
    }

    @Test
    fun `first test inserts data`() {
        repository.insert(testVerse) // Mutates shared state
    }

    @Test
    fun `second test reads data`() {
        val result = repository.getAll() // Depends on first test!
    }
}

// GOOD: Fresh state per test
class VerseRepositoryTest {
    private lateinit var repository: VerseRepositoryImpl

    @BeforeTest
    fun setup() {
        val db = createInMemoryDatabase()
        repository = VerseRepositoryImpl(db)
    }

    @Test
    fun `returns inserted verse`() {
        repository.insert(testVerse)

        val result = repository.getVerses(bookId = 1, chapter = 1, Language.RU)

        assertEquals(listOf(testVerse), result.getOrThrow())
    }
}
```

---

## Fakes Over Mocks

Use hand-written fakes instead of mocking frameworks. Fakes are simpler, more readable, and work across KMP platforms.

```kotlin
// BAD: Mocking framework
@Test
fun `loads chapter from repository`() {
    val mockRepo = mock<VerseRepository>()
    whenever(mockRepo.getVerses(any(), any(), any()))
        .thenReturn(Result.success(testVerses))
    val useCase = GetChapterUseCase(mockRepo)

    val result = runBlocking { useCase(1, 1, Language.RU) }

    verify(mockRepo).getVerses(1, 1, Language.RU) // Tests implementation detail
}

// GOOD: Hand-written fake
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
    ): Result<List<Verse>> {
        if (shouldFail) return Result.failure(RuntimeException("DB error"))
        val data = verses[Triple(bookId, chapter, language)]
        return if (data != null) Result.success(data)
        else Result.failure(RuntimeException("Not found"))
    }
}

@Test
fun `returns verses from repository`() {
    // Arrange
    val repository = FakeVerseRepository()
    repository.setVerses(1, 1, Language.RU, testVerses)
    val useCase = GetChapterUseCase(repository)

    // Act
    val result = runBlocking { useCase(1, 1, Language.RU) }

    // Assert
    assertEquals(testVerses, result.getOrThrow())
}
```

---

## Per-Layer Testing

### Domain Layer (Unit Tests)

Pure Kotlin, no platform dependencies. Test use cases with fakes.

```kotlin
// Location: shared/src/commonTest/kotlin/.../feature/{name}/domain/

class GetChapterUseCaseTest {
    private val repository = FakeVerseRepository()
    private val useCase = GetChapterUseCase(repository)

    @Test
    fun `returns verses for valid chapter`() {
        repository.setVerses(1, 1, Language.RU, testVerses)

        val result = runBlocking { useCase(1, 1, Language.RU) }

        assertEquals(testVerses, result.getOrThrow())
    }

    @Test
    fun `returns failure when repository fails`() {
        repository.setShouldFail(true)

        val result = runBlocking { useCase(1, 1, Language.RU) }

        assertTrue(result.isFailure)
    }
}
```

### Data Layer (Integration Tests)

Test with real database (in-memory SQLite). Verify SQL queries and mapping.

```kotlin
// Location: shared/src/commonTest/kotlin/.../feature/{name}/data/

class VerseRepositoryImplTest {
    private lateinit var db: BibleDatabase
    private lateinit var repository: VerseRepositoryImpl

    @BeforeTest
    fun setup() {
        val driver = JdbcSqliteDriver(JdbcSqliteDriver.IN_MEMORY)
        BibleDatabase.Schema.create(driver)
        db = BibleDatabase(driver)
        insertTestData(db)
        repository = VerseRepositoryImpl(db)
    }

    @Test
    fun `returns verses ordered by id`() {
        val result = repository.getVerses(bookId = 1, chapter = 1, Language.RU)

        val verses = result.getOrThrow()
        assertEquals(listOf(1L, 2L, 3L), verses.map { it.id })
    }
}
```

### Presentation Layer (ViewModel Tests)

Test state transitions using Turbine for Flow assertions.

```kotlin
// Location: shared/src/commonTest/kotlin/.../feature/{name}/presentation/

class ReaderViewModelTest {
    private val repository = FakeVerseRepository()
    private val useCase = GetChapterUseCase(repository)
    private val testDispatcher = StandardTestDispatcher()

    @Test
    fun `emits loading then success on chapter load`() = runTest {
        repository.setVerses(1, 1, Language.RU, testVerses)
        val viewModel = ReaderViewModel(useCase, testDispatcher)

        viewModel.state.test {
            assertEquals(ReaderState(), awaitItem()) // Initial

            viewModel.onEvent(ReaderEvent.LoadChapter(1, 1))

            val loading = awaitItem()
            assertTrue(loading.isLoading)

            val success = awaitItem()
            assertFalse(success.isLoading)
            assertEquals(testVerses, success.verses)
        }
    }
}
```

---

## Flow & ViewModel Testing

### Use Turbine for StateFlow Testing

```kotlin
// BAD: Collecting flow manually with timeouts
@Test
fun `state updates`() = runTest {
    val states = mutableListOf<State>()
    val job = launch { viewModel.state.collect { states.add(it) } }
    viewModel.onEvent(SomeEvent)
    delay(100) // Fragile timing
    assertEquals(2, states.size)
    job.cancel()
}

// GOOD: Turbine provides deterministic assertions
@Test
fun `state updates on event`() = runTest {
    viewModel.state.test {
        assertEquals(InitialState, awaitItem())

        viewModel.onEvent(SomeEvent)
        assertEquals(UpdatedState, awaitItem())

        cancelAndConsumeRemainingEvents()
    }
}
```

### Use StandardTestDispatcher for Coroutine Control

```kotlin
// BAD: Using real dispatchers in tests
@Test
fun `loads data`() = runBlocking {
    val viewModel = MyViewModel(useCase) // Uses Dispatchers.Main
    delay(1000) // Wait and hope
    assertEquals(expected, viewModel.state.value)
}

// GOOD: Injectable test dispatcher
@Test
fun `loads data`() = runTest {
    val viewModel = MyViewModel(useCase, StandardTestDispatcher(testScheduler))

    viewModel.loadData()
    advanceUntilIdle()

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
    val verse = testVerse()
    // ...
}

@Test
fun `test with specific field`() {
    val verse = testVerse(text = "Custom text", cssClass = "red")
    // ...
}
```

---

## What Not to Test

- Data classes (auto-generated equals/hashCode/copy)
- Enum values
- Direct delegation (a function that just calls another function)
- Framework code (Compose UI rendering, Koin module wiring)
- Third-party library behavior

Focus testing effort on:
- Business logic (use cases)
- Data mapping and SQL queries (repositories)
- State transitions (ViewModels)
- Edge cases and error paths
- Custom parsers and converters

---

## Summary Checklist

### Structure
- [ ] Every test follows AAA (Arrange-Act-Assert)
- [ ] One concept per test
- [ ] Tests are independent (no shared mutable state)
- [ ] Descriptive backtick-quoted test names

### Strategy
- [ ] Domain layer: unit tests with fakes
- [ ] Data layer: integration tests with in-memory DB
- [ ] Presentation layer: ViewModel tests with Turbine
- [ ] Fakes preferred over mocking frameworks

### Quality
- [ ] Tests document behavior (readable as specs)
- [ ] Test data uses factory functions with defaults
- [ ] No fragile timing (no `delay()` in tests)
- [ ] No tests for trivial/generated code
