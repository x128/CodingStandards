# Architecture Standards

Standards for structuring Kotlin Multiplatform projects with Clean Architecture.

## Table of Contents
1. [Layer Separation](#layer-separation)
2. [Package Organization](#package-organization)
3. [Domain Layer](#domain-layer)
4. [Data Layer](#data-layer)
5. [Presentation Layer](#presentation-layer)
6. [Dependency Injection](#dependency-injection)
7. [Error Handling](#error-handling)
8. [Navigation](#navigation)

---

## Layer Separation

Three layers with strict dependency direction: Presentation -> Domain <- Data.

```
┌──────────────────────────────┐
│   Presentation (UI)          │  Compose screens, ViewModels, UI state
│   depends on: Domain         │
├──────────────────────────────┤
│   Domain (Business Logic)    │  Use cases, entities, repository interfaces
│   depends on: nothing        │
├──────────────────────────────┤
│   Data (Implementation)      │  Repository impls, DB, API, preferences
│   depends on: Domain         │
└──────────────────────────────┘
```

```kotlin
// BAD: UI layer directly accesses database
@Composable
fun ReaderScreen(db: BibleDatabase) {
    val verses = db.verseQueries.selectByChapter(1, 1).executeAsList()
    LazyColumn { items(verses) { VerseText(it) } }
}

// BAD: Domain depends on framework types
class GetChapterUseCase(private val db: BibleDatabase) // SQLDelight type in domain!

// GOOD: Domain defines interface, Data implements
// Domain layer
interface VerseRepository {
    suspend fun getVerses(bookId: Int, chapter: Int, language: Language): Result<List<Verse>>
}

// Data layer
class VerseRepositoryImpl(private val db: BibleDatabase) : VerseRepository {
    override suspend fun getVerses(bookId: Int, chapter: Int, language: Language): Result<List<Verse>> {
        // SQLDelight queries here
    }
}

// Domain layer use case depends on interface only
class GetChapterUseCase(private val repository: VerseRepository) {
    suspend operator fun invoke(bookId: Int, chapter: Int, language: Language): Result<List<Verse>> {
        return repository.getVerses(bookId, chapter, language)
    }
}
```

---

## Package Organization

Organize by feature first, then by layer within each feature.

```
// BAD: Organized by layer (everything in one place)
domain/
  GetChapterUseCase.kt
  SearchBibleUseCase.kt
  GetBooksUseCase.kt
data/
  VerseRepositoryImpl.kt
  SearchRepositoryImpl.kt
  BookRepositoryImpl.kt
presentation/
  ReaderViewModel.kt
  SearchViewModel.kt
  BookListViewModel.kt

// GOOD: Organized by feature, layered within
core/
  database/           # Shared DB infrastructure
  model/              # Shared domain entities
  text/               # Shared text parsing
  preferences/        # Shared preferences
  di/CoreModule.kt

feature/
  reader/
    domain/
      GetChapterUseCase.kt
      error/ReaderError.kt
    data/
      VerseRepository.kt       # Interface
      VerseRepositoryImpl.kt   # Implementation
    presentation/
      ReaderViewModel.kt
      ReaderState.kt
      ReaderEvent.kt
      ReaderScreen.kt
      component/
        VerseText.kt
    di/ReaderModule.kt

  search/
    domain/
      SearchBibleUseCase.kt
      error/SearchError.kt
    data/
      SearchRepository.kt
      SearchRepositoryImpl.kt
    presentation/
      SearchViewModel.kt
      SearchState.kt
      SearchEvent.kt
      SearchScreen.kt
    di/SearchModule.kt
```

---

## Domain Layer

### Use Cases

Each use case represents a single user action. Implement `operator fun invoke` for clean call syntax.

```kotlin
// BAD: Use case with multiple responsibilities
class BibleUseCase(private val repo: VerseRepository) {
    suspend fun getChapter(bookId: Int, chapter: Int, language: Language): Result<List<Verse>> { ... }
    suspend fun search(query: String, scope: SearchScope): Result<List<SearchResult>> { ... }
    suspend fun getBooks(): Result<List<Book>> { ... }
}

// GOOD: Single-responsibility use cases
class GetChapterUseCase(private val repository: VerseRepository) {
    suspend operator fun invoke(
        bookId: Int,
        chapter: Int,
        language: Language
    ): Result<List<Verse>> {
        return repository.getVerses(bookId, chapter, language)
    }
}

// Called cleanly
val verses = getChapterUseCase(bookId = 1, chapter = 1, language = Language.RU)
```

### Domain Entities

Pure data classes with no framework dependencies.

```kotlin
// BAD: Domain entity with framework annotations
@Entity(tableName = "verses")
data class Verse(
    @PrimaryKey val id: Long,
    @ColumnInfo(name = "book_id") val bookId: Int,
    // ...
)

// GOOD: Plain data class
data class Verse(
    val id: Long,
    val bookId: Int,
    val chapter: Int,
    val verseNumber: Int,
    val text: String,
    val alignId: String,
    val cssClass: String
)
```

---

## Data Layer

### Repository Pattern

Repository interface lives in domain, implementation lives in data.

```kotlin
// Domain layer - interface
interface BookRepository {
    suspend fun getAllBooks(): Result<List<Book>>
    suspend fun getBooksByGroup(groupId: Int): Result<List<Book>>
    suspend fun getBookById(id: Int): Result<Book>
}

// Data layer - implementation with DB mapping
class BookRepositoryImpl(
    private val bookQueries: BookQueries
) : BookRepository {

    override suspend fun getAllBooks(): Result<List<Book>> {
        return runCatching {
            bookQueries.selectAll().executeAsList().map { it.toDomain() }
        }
    }

    private fun BooksRow.toDomain() = Book(
        id = id.toInt(),
        nameRu = name_ru,
        shortEn = ShortEN,
        groupId = group_.toInt(),
        chapterCount = NChapters.toInt()
    )
}
```

### Mapping

Map between DB/API models and domain models at the repository boundary.

```kotlin
// BAD: Leaking DB model to domain
class VerseRepositoryImpl(private val db: BibleDatabase) : VerseRepository {
    override suspend fun getVerses(...): Result<List<SelectRussianVerses>> { // DB type!
        return runCatching { db.verseQueries.selectRussianVerses(...).executeAsList() }
    }
}

// GOOD: Map to domain model
class VerseRepositoryImpl(private val db: BibleDatabase) : VerseRepository {
    override suspend fun getVerses(
        bookId: Int,
        chapter: Int,
        language: Language
    ): Result<List<Verse>> {
        return runCatching {
            val rows = when (language) {
                Language.RU -> db.verseQueries.selectRussianVerses(bookId, chapter)
                Language.CS -> db.verseQueries.selectChurchSlavonicVerses(bookId, chapter)
                Language.EL -> db.verseQueries.selectGreekVerses(bookId, chapter)
            }
            rows.executeAsList().map { it.toDomainVerse() }
        }
    }
}
```

---

## Presentation Layer

### Unidirectional Data Flow (UDF)

Events flow up from UI, state flows down from ViewModel.

```kotlin
// State: immutable data class
data class ReaderState(
    val book: Book? = null,
    val chapter: Int = 1,
    val language: Language = Language.RU,
    val verses: List<Verse> = emptyList(),
    val isLoading: Boolean = false,
    val error: ReaderError? = null
)

// Events: sealed interface
sealed interface ReaderEvent {
    data class LoadChapter(val bookId: Int, val chapter: Int) : ReaderEvent
    data class ChangeLanguage(val language: Language) : ReaderEvent
    data class ChangeChapter(val chapter: Int) : ReaderEvent
}

// ViewModel: processes events, emits state
class ReaderViewModel(
    private val getChapterUseCase: GetChapterUseCase,
    private val dispatcher: CoroutineDispatcher
) : ScreenModel() {

    private val _state = MutableStateFlow(ReaderState())
    val state: StateFlow<ReaderState> = _state.asStateFlow()

    fun onEvent(event: ReaderEvent) {
        when (event) {
            is ReaderEvent.LoadChapter -> loadChapter(event.bookId, event.chapter)
            is ReaderEvent.ChangeLanguage -> changeLanguage(event.language)
            is ReaderEvent.ChangeChapter -> changeChapter(event.chapter)
        }
    }

    private fun loadChapter(bookId: Int, chapter: Int) {
        screenModelScope.launch(dispatcher) {
            _state.update { it.copy(isLoading = true, error = null) }
            getChapterUseCase(bookId, chapter, _state.value.language)
                .onSuccess { verses ->
                    _state.update { it.copy(verses = verses, isLoading = false) }
                }
                .onFailure { error ->
                    _state.update { it.copy(error = mapError(error), isLoading = false) }
                }
        }
    }
}
```

### Compose Screen

Screen observes state and sends events. No business logic in Compose.

```kotlin
// BAD: Logic in Compose
@Composable
fun ReaderScreen(db: BibleDatabase) {
    var verses by remember { mutableStateOf(emptyList<Verse>()) }
    LaunchedEffect(Unit) {
        verses = db.verseQueries.select(1, 1).executeAsList() // Data access in UI!
    }
}

// GOOD: Screen observes state, delegates events
@Composable
fun ReaderScreen(viewModel: ReaderViewModel) {
    val state by viewModel.state.collectAsState()

    ReaderContent(
        state = state,
        onEvent = viewModel::onEvent
    )
}

@Composable
private fun ReaderContent(
    state: ReaderState,
    onEvent: (ReaderEvent) -> Unit
) {
    // Pure UI rendering from state
    if (state.isLoading) {
        CircularProgressIndicator()
    } else {
        LazyColumn {
            items(state.verses) { verse ->
                VerseText(verse = verse)
            }
        }
    }
}
```

---

## Dependency Injection

### Module per Feature

Each feature has its own Koin module. Core has a shared module.

```kotlin
// BAD: One giant module
val appModule = module {
    single { DatabaseDriverFactory(get()).createDriver() }
    single { BibleDatabase(get()) }
    single<VerseRepository> { VerseRepositoryImpl(get()) }
    single<BookRepository> { BookRepositoryImpl(get()) }
    single<SearchRepository> { SearchRepositoryImpl(get()) }
    factory { GetChapterUseCase(get()) }
    factory { SearchBibleUseCase(get()) }
    factory { GetBooksUseCase(get()) }
    factory { ReaderViewModel(get(), get()) }
    factory { SearchViewModel(get(), get()) }
    factory { BookListViewModel(get(), get()) }
}

// GOOD: Modular DI
val coreModule = module {
    single { DatabaseDriverFactory(get()).createDriver() }
    single { BibleDatabase(get()) }
    single<CoroutineDispatcher>(named("io")) { Dispatchers.IO }
}

val readerModule = module {
    single<VerseRepository> { VerseRepositoryImpl(get()) }
    factory { GetChapterUseCase(get()) }
    factory { ReaderViewModel(get(), get(named("io"))) }
}

val searchModule = module {
    single<SearchRepository> { SearchRepositoryImpl(get()) }
    factory { SearchBibleUseCase(get()) }
    factory { SearchViewModel(get(), get(named("io"))) }
}

// Aggregated
val appModule = module {
    includes(coreModule, readerModule, searchModule)
}
```

### Scoping Rules

```kotlin
// single: shared instances (repositories, database)
single<VerseRepository> { VerseRepositoryImpl(get()) }

// factory: new instance per injection (use cases, ViewModels)
factory { GetChapterUseCase(get()) }
factory { ReaderViewModel(get(), get()) }
```

---

## Error Handling

### Sealed Error Types per Feature

```kotlin
// BAD: String errors or generic exceptions
class GetChapterUseCase(...) {
    suspend operator fun invoke(...): Result<List<Verse>> {
        return Result.failure(Exception("Book not found")) // Unstructured
    }
}

// GOOD: Sealed error hierarchy
sealed class ReaderError {
    data class BookNotFound(val bookId: Int) : ReaderError()
    data class ChapterOutOfRange(val chapter: Int, val maxChapter: Int) : ReaderError()
    data class DatabaseError(val message: String) : ReaderError()
}

// ViewModel maps errors to UI messages
private fun mapError(error: ReaderError): String = when (error) {
    is ReaderError.BookNotFound -> "Book not found"
    is ReaderError.ChapterOutOfRange -> "Chapter ${error.chapter} does not exist (max: ${error.maxChapter})"
    is ReaderError.DatabaseError -> "Database error: ${error.message}"
}
```

---

## Navigation

### Type-Safe Screen Definitions

Each screen is a Voyager Screen with its required parameters.

```kotlin
// BAD: String-based navigation with manual argument parsing
navigator.navigate("reader/$bookId/$chapter")

// GOOD: Type-safe screen objects
data class ReaderScreen(
    val bookId: Int,
    val chapter: Int
) : Screen {
    @Composable
    override fun Content() {
        val viewModel = koinScreenModel<ReaderViewModel>()
        // ...
    }
}

// Navigate with type safety
navigator.push(ReaderScreen(bookId = 51, chapter = 1))
```

---

## Summary Checklist

### Architecture
- [ ] Three layers: Presentation -> Domain <- Data
- [ ] Domain has zero framework dependencies
- [ ] Repository interfaces in domain, implementations in data
- [ ] DB/API models mapped to domain models at repository boundary

### Features
- [ ] Package by feature, layer within feature
- [ ] One use case per user action
- [ ] Sealed error types per feature
- [ ] Koin module per feature

### Presentation
- [ ] Immutable state data class
- [ ] Sealed event interface
- [ ] ViewModel processes events, emits state
- [ ] Compose screens have zero business logic
- [ ] Unidirectional data flow (events up, state down)

### DI
- [ ] All dependencies injected via constructor
- [ ] Dispatchers are injectable
- [ ] Repositories as single, use cases and ViewModels as factory
