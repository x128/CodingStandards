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
┌─────────────────────────┐
│   Presentation          │  Compose screens, ViewModels, UI state
│   depends on: Domain    │
├─────────────────────────┤
│   Domain (App Logic)    │  Use cases, entities, repository interfaces
│   depends on: nothing   │
├─────────────────────────┤
│   Data                  │  Repository implementations, DB, API, preferences
│   depends on: Domain    │
└─────────────────────────┘
```

```kotlin
// BAD: UI layer directly accesses database
@Composable
fun ReaderScreen(db: BibleDatabase) {
    val verses = db.verseQueries.selectByChapter(1, 1).executeAsList()
    LazyColumn { items(verses) { VerseText(it) } }
}

// BAD: Domain depends on framework types (BibleDatabase is a SQLDelight type)
class GetChapterUseCase(private val db: BibleDatabase)

// GOOD: Domain defines interface, Data implements
// Domain layer
interface VerseRepository {
    suspend fun getVerses(bookId: Int, chapter: Int, language: Language): List<Verse>
}

// Data layer
class DatabaseVerseRepository(private val db: BibleDatabase) : VerseRepository {
    override suspend fun getVerses(bookId: Int, chapter: Int, language: Language): List<Verse> =
        storageCall("Cannot read verses") {
            val rows = when (language) {
                Language.RU -> db.verseQueries.selectRussianVerses(bookId, chapter)
                Language.CS -> db.verseQueries.selectChurchSlavonicVerses(bookId, chapter)
                Language.EL -> db.verseQueries.selectGreekVerses(bookId, chapter)
            }
            rows.executeAsList().map { it.toDomainVerse() }
        }
}

// Domain layer: the use case depends on the interfaces only
class GetChapterUseCase(
    private val bookRepository: BookRepository,
    private val verseRepository: VerseRepository
)
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
  DatabaseVerseRepository.kt
  DatabaseSearchRepository.kt
  DatabaseBookRepository.kt
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
      GetChapterResult.kt
      VerseRepository.kt           # Interface
    data/
      DatabaseVerseRepository.kt   # Implementation
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
      SearchRepository.kt
    data/
      DatabaseSearchRepository.kt
    presentation/
      SearchViewModel.kt
      SearchState.kt
      SearchEvent.kt
      SearchScreen.kt
    di/SearchModule.kt
```

### Naming Conventions

| Component | Pattern | Example |
|---|---|---|
| Use case | `{Verb}{Thing}UseCase` | `GetChapterUseCase` |
| Repository interface | `{Thing}Repository` | `VerseRepository` |
| Repository implementation | `{WhatMakesItThisOne}{Thing}Repository` | `DatabaseVerseRepository` |
| ViewModel | `{Feature}ViewModel` | `ReaderViewModel` |
| State | `{Feature}State` | `ReaderState` |
| Event | `{Feature}Event` | `ReaderEvent` |
| DI module | `{feature}Module` (top-level val) | `val readerModule` |
| SQLDelight | One `.sq` file per table | `ru.sq`, `books.sq` |

Use cases implement `operator fun invoke()` for clean call-site syntax.

---

## Domain Layer

The domain layer is the **stable center** of the application. Everything else depends on it; it depends on nothing. All business logic lives here: what is checked, what is decided, and in what order data is read and changed: a rule that is true of an entity whichever use case asks lives with the entity, and application-specific rules live in use cases. This is the most important architectural invariant: if business logic creeps into ViewModels or repositories, the architecture is broken.

### Use Cases

#### Principles

These hold in any style of code: objects, functions, streams, state machines.

**What a use case is.** A use case holds application-specific business rules. It is described by its input, its output, and the rules between them: what is checked, what is decided, and what is read and changed, in what order. A rule that is true of an entity whichever use case asks is not in the use case: it lives with the entities, and the use case calls it. What the rule answers, a refusal included, is declared with the rule, so no use case decides it again. An entity knows no use case.

**What a use case knows.** A use case reaches other code only through what the domain layer declares. It names no API of a screen, a database, a file system, a network or a platform.

**The form is free.** The same use case can be a class with one method, a function, a publisher or a state machine. A change of form does not change its input, its output or its rules.

**Not a user action.** A use case is not a user action. A user action is a tap, or what a screen sends when the user taps: something in presentation, a plain value with no check and no decision. It may start a use case, and so may a timer or a background task. But use cases are not found by counting buttons: several user actions can lead to one use case, one to several, and some to none.

**From requirements to code.** The requirements text of a use case has a name, an input, an output and rules, in the words of the subject (book, chapter, verse). The code has the same four parts under the same words. Every outcome that the text names, such as "book not found", has its own name in what the use case gives back.

**Failures that the text does not name.** A failure that the text does not name, such as a disk that cannot be read, is not an outcome of the use case. The use case makes no decision on it, does not rename it and does not hide it. It may clean up; then it hands the cause on to the caller unchanged, and the use case ends. Every form has to give such a failure a way to the caller. If the caller has to tell it apart, the text names it first. Cancellation by the caller is not an outcome and not a failure. The use case does not turn it into either: it may clean up, and it ends with no outcome.

**One use case or two.** A use case has its own input, its own output and its own rules. Two use cases that look alike today stay two when they change for different reasons.

**A request with no rules.** A request can have nothing to check and nothing to decide: read the list of books and show it. There are two ways to write it. The caller uses the interface that the domain layer declares, and no use case is written. Or a use case is written whose body is that one call, and the caller uses only use cases. Neither is wrong. A project picks one, records it in the Decisions Log of its implementation plan, and follows it everywhere.

**Where a rule belongs.** To change a business rule, you edit domain code: a use case, an entity, or another type or function of the domain layer. If you have to edit a screen, storage code or wiring to change the rule itself, the rule is in the wrong place.

#### Implementation

In this standard a use case is a Kotlin class in the domain layer, `{Verb}{Thing}UseCase`, with one public function, `operator fun invoke`. Each part of the requirements text becomes one part of the class.

```
Get a chapter
Input:   the book id, the chapter, the language
Output:  the verses of the chapter; or book not found; or chapter out of range
Rules:   1. Get the book. If there is none: book not found.
         2. Check that the book has this chapter. If not: chapter out of range.
         3. Get the verses of the chapter in this language.
```

```kotlin
// BAD: rules 1 and 2 of the text are missing
class GetChapterUseCase(private val verseRepository: VerseRepository) {
    suspend operator fun invoke(bookId: Int, chapter: Int, language: Language) =
        verseRepository.getVerses(bookId, chapter, language)
}

// GOOD: the name, the input, the output and the rules of the text
data class Book(val id: Int, val chapterCount: Int) {
    fun hasChapter(chapter: Int) = chapter in 1..chapterCount
}

interface BookRepository {
    suspend fun getBookById(bookId: Int): Book?
}

interface VerseRepository {
    suspend fun getVerses(bookId: Int, chapter: Int, language: Language): List<Verse>
}

sealed interface GetChapterResult {
    data class Verses(val verses: List<Verse>) : GetChapterResult
    data class BookNotFound(val bookId: Int) : GetChapterResult
    data class ChapterOutOfRange(val chapter: Int, val chapterCount: Int) : GetChapterResult
}

class GetChapterUseCase(
    private val bookRepository: BookRepository,
    private val verseRepository: VerseRepository
) {
    suspend operator fun invoke(bookId: Int, chapter: Int, language: Language): GetChapterResult {
        val book = bookRepository.getBookById(bookId)
            ?: return GetChapterResult.BookNotFound(bookId)
        if (!book.hasChapter(chapter)) {
            return GetChapterResult.ChapterOutOfRange(chapter, book.chapterCount)
        }
        return GetChapterResult.Verses(verseRepository.getVerses(bookId, chapter, language))
    }
}
```

When the text names more than one outcome, each is a case of the use case's own sealed type. When it names one, `invoke` returns that value itself. A failure that the text does not name leaves `invoke` as an exception. Where Swift calls the use case, `invoke` is marked `@Throws(StorageException::class, CancellationException::class)`: then a storage failure and a cancellation reach Swift as errors, and a bug still ends the app. The compiler requires `CancellationException` in the list of a `suspend` function. In Swift both arrive as an `NSError` that holds the Kotlin exception in `userInfo["KotlinException"]`; SWIFT.md, "Error Handling", shows the one function that catches them.

A refusal that a rule of an entity gives, the same for every use case that asks, is declared once, next to that rule, and the rule returns it. The sealed type of each use case that asks has one case that carries it. A screen that switches a button off asks the same function, and presentation writes the message of each refusal in one place. Such a type holds the answers of one rule; it is not a type of errors of a feature.

```kotlin
// BAD: the rule of the book is copied into each use case that asks
if (book.status == BookStatus.Downloading) return AddBookmarkResult.BookIsDownloading
if (book.status == BookStatus.Removed) return AddBookmarkResult.BookIsRemoved

// GOOD: the rule and its refusal are written once, with the book
enum class NoteRefusal { BookIsDownloading, BookIsRemoved }

data class Book(val id: Int, val chapterCount: Int, val status: BookStatus) {
    fun refusalOfNotes(): NoteRefusal? = when (status) {
        BookStatus.Available -> null
        BookStatus.Downloading -> NoteRefusal.BookIsDownloading
        BookStatus.Removed -> NoteRefusal.BookIsRemoved
    }
}

sealed interface AddBookmarkResult {
    data object Added : AddBookmarkResult
    data class NotAllowed(val refusal: NoteRefusal) : AddBookmarkResult
    data class BookNotFound(val bookId: Int) : AddBookmarkResult
}

class AddBookmarkUseCase(
    private val bookRepository: BookRepository,
    private val bookmarkRepository: BookmarkRepository
) {
    suspend operator fun invoke(bookId: Int, chapter: Int, verse: Int): AddBookmarkResult {
        val book = bookRepository.getBookById(bookId) ?: return AddBookmarkResult.BookNotFound(bookId)
        book.refusalOfNotes()?.let { return AddBookmarkResult.NotAllowed(it) }
        bookmarkRepository.addBookmark(bookId, chapter, verse)
        return AddBookmarkResult.Added
    }
}
```

A use case that gives values over time has an `invoke` that is not `suspend` and returns a `Flow`. The outcomes that the text names are the values of the `Flow`. A failure that the text does not name ends the `Flow` as an exception at the collector. `@Throws` on `invoke` does not cover this exception, so Swift does not collect the `Flow` itself: Kotlin code collects it and catches the exception.

The same use case in another style keeps its input, its output and its rules. The two forms below only show this; code under this standard uses the class.

As a function:

```kotlin
typealias GetBookById = suspend (bookId: Int) -> Book?
typealias GetVerses = suspend (bookId: Int, chapter: Int, language: Language) -> List<Verse>
typealias GetChapter = suspend (bookId: Int, chapter: Int, language: Language) -> GetChapterResult

// What the use case needs from outside is passed in first; the function that comes back is the use case
fun getChapterWith(getBookById: GetBookById, getVerses: GetVerses): GetChapter = { bookId, chapter, language ->
    val book = getBookById(bookId)
    when {
        book == null -> GetChapterResult.BookNotFound(bookId)
        !book.hasChapter(chapter) -> GetChapterResult.ChapterOutOfRange(chapter, book.chapterCount)
        else -> GetChapterResult.Verses(getVerses(bookId, chapter, language))
    }
}
```

As a Combine publisher in Swift. The outcomes that the text names are its `Output`; a failure that the text does not name is its `Failure`:

```swift
enum GetChapterResult {
    case verses([Verse])
    case bookNotFound(bookId: Int)
    case chapterOutOfRange(chapter: Int, chapterCount: Int)
}

protocol BookRepository {
    func book(id: Int) -> Future<Book?, Error>
}

protocol VerseRepository {
    func verses(bookId: Int, chapter: Int, language: Language) -> Future<[Verse], Error>
}

struct GetChapter {
    let bookRepository: BookRepository
    let verseRepository: VerseRepository

    func callAsFunction(bookId: Int, chapter: Int, language: Language) -> AnyPublisher<GetChapterResult, Error> {
        Deferred { bookRepository.book(id: bookId) }
            .flatMap { book -> AnyPublisher<GetChapterResult, Error> in
                guard let book else {
                    return result(.bookNotFound(bookId: bookId))
                }
                guard book.hasChapter(chapter) else {
                    return result(.chapterOutOfRange(chapter: chapter, chapterCount: book.chapterCount))
                }
                return verseRepository.verses(bookId: bookId, chapter: chapter, language: language)
                    .map(GetChapterResult.verses)
                    .eraseToAnyPublisher()
            }
            .eraseToAnyPublisher()
    }

    private func result(_ result: GetChapterResult) -> AnyPublisher<GetChapterResult, Error> {
        Just(result).setFailureType(to: Error.self).eraseToAnyPublisher()
    }
}
```

### Use Case Independence

Use cases depend **only** on what the domain layer declares: entities and repository interfaces. They never depend on ViewModels, UI types, framework classes, or other use cases. This makes them independently testable and reusable.

```kotlin
// BAD: Use case depends on another use case
class SelectChapterUseCase(
    private val getChapter: GetChapterUseCase,
    private val getBookGroups: GetBookGroupsUseCase
) {
    suspend operator fun invoke(bookId: Int, chapter: Int, language: Language): GetChapterResult {
        val groups = getBookGroups()
        val book = groups.flatMap { it.books }.find { it.id == bookId }
            ?: return GetChapterResult.BookNotFound(bookId)
        return getChapter(book.id, chapter, language)
    }
}

// BAD: Use case depends on framework type (BibleDatabase is a SQLDelight type)
class GetChapterUseCase(
    private val db: BibleDatabase
)

// BAD: Use case has state or side effects beyond repository calls: lastBookId is state, and invoke writes it as a side effect
class GetChapterUseCase(
    private val bookRepository: BookRepository,
    private val verseRepository: VerseRepository
) {
    private var lastBookId: Int = 0

    suspend operator fun invoke(bookId: Int, chapter: Int, language: Language): GetChapterResult {
        lastBookId = bookId
        val book = bookRepository.getBookById(bookId)
            ?: return GetChapterResult.BookNotFound(bookId)
        if (!book.hasChapter(chapter)) {
            return GetChapterResult.ChapterOutOfRange(chapter, book.chapterCount)
        }
        return GetChapterResult.Verses(verseRepository.getVerses(bookId, chapter, language))
    }
}

// GOOD: Use case depends only on what the domain layer declares, is stateless
class GetChapterUseCase(
    private val bookRepository: BookRepository,
    private val verseRepository: VerseRepository
) {
    suspend operator fun invoke(bookId: Int, chapter: Int, language: Language): GetChapterResult {
        val book = bookRepository.getBookById(bookId)
            ?: return GetChapterResult.BookNotFound(bookId)
        if (!book.hasChapter(chapter)) {
            return GetChapterResult.ChapterOutOfRange(chapter, book.chapterCount)
        }
        return GetChapterResult.Verses(verseRepository.getVerses(bookId, chapter, language))
    }
}
```

### Business Logic Lives in the Domain Layer, Not ViewModels

If a ViewModel contains `if/when` logic beyond event dispatch and result-to-state mapping, that logic belongs in the domain layer: in a use case or an entity.

```kotlin
// BAD: Business logic in ViewModel: it validates that the book exists and that the chapter is in range
class ReaderViewModel(
    private val bookRepository: BookRepository,
    private val verseRepository: VerseRepository
) : ViewModel() {
    private fun loadChapter(bookId: Int, chapter: Int) {
        viewModelScope.launch {
            val book = bookRepository.getBookById(bookId)
            if (book == null) {
                _state.update { it.copy(error = "Book not found") }
                return@launch
            }
            if (chapter < 1 || chapter > book.chapterCount) {
                _state.update { it.copy(error = "Invalid chapter") }
                return@launch
            }
            val verses = verseRepository.getVerses(bookId, chapter, state.value.language)
            _state.update { it.copy(verses = verses) }
        }
    }
}

// GOOD: ViewModel delegates to use case, only maps result to state
class ReaderViewModel(private val getChapter: GetChapterUseCase) : ViewModel() {
    private fun loadChapter(bookId: Int, chapter: Int) {
        viewModelScope.launchCatchingStorage(onStorageFailure = { showError("Could not load the chapter") }) {
            _state.update { it.copy(isLoading = true) }
            show(getChapter(bookId, chapter, _state.value.language))
        }
    }

    private fun show(result: GetChapterResult) = when (result) {
        is GetChapterResult.Verses -> _state.update { it.copy(verses = result.verses, isLoading = false) }
        is GetChapterResult.BookNotFound -> showError("Book not found")
        is GetChapterResult.ChapterOutOfRange -> showError("Invalid chapter")
    }

    private fun showError(message: String) = _state.update { it.copy(error = message, isLoading = false) }
}
```

### Domain Entities

Plain classes that hold their data and their own rules, with no framework dependencies — no `@Entity`, `@Serializable`, or other annotations. When persistence or serialization is needed, create DTO classes at the data/serialization boundary with `toDomain()` / `toDto()` mapping functions. This protects domain evolution from breaking serialized data.

```kotlin
// BAD: Domain entity with framework annotations
@Entity(tableName = "verses")
data class Verse(
    @PrimaryKey val id: Long,
    @ColumnInfo(name = "book_id") val bookId: Int,
    // ...
)

// BAD: @Serializable couples domain to serialization format
@Serializable
data class Zone(val id: String, val type: ZoneType, ...)

// GOOD: Plain domain class + separate DTO at boundary
data class Zone(val id: ZoneId, val type: ZoneType, ...)

// DTO (data/serialization layer)
@Serializable
data class ZoneDto(val id: String, val type: String, ...)
fun Zone.toDto() = ZoneDto(id.value, type.name, ...)
fun ZoneDto.toDomain() = Zone(ZoneId(id), ZoneType.valueOf(type), ...)
```

---

## Data Layer

### Repository Pattern

Repository interface lives in domain, implementation lives in data.

```kotlin
// Domain layer - interface
interface BookRepository {
    suspend fun getAllBooks(): List<Book>
    suspend fun getBooksByGroup(groupId: Int): List<Book>
    suspend fun getBookById(bookId: Int): Book?
}

// Data layer - implementation with DB mapping
class DatabaseBookRepository(
    private val bookQueries: BookQueries
) : BookRepository {

    override suspend fun getAllBooks(): List<Book> = books(bookQueries.selectAll())
    override suspend fun getBooksByGroup(groupId: Int): List<Book> = books(bookQueries.selectByGroup(groupId))
    override suspend fun getBookById(bookId: Int): Book? = books(bookQueries.selectById(bookId)).firstOrNull()

    private fun books(query: Query<BooksRow>): List<Book> =
        storageCall("Cannot read books") { query.executeAsList().map { it.toDomain() } }

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
// BAD: Leaking DB model to domain: getVerses returns SelectRussianVerses, a DB type
interface VerseRepository {
    suspend fun getVerses(bookId: Int, chapter: Int, language: Language): List<SelectRussianVerses>
}

class DatabaseVerseRepository(private val db: BibleDatabase) : VerseRepository {
    override suspend fun getVerses(bookId: Int, chapter: Int, language: Language): List<SelectRussianVerses> =
        storageCall("Cannot read verses") { db.verseQueries.selectRussianVerses(bookId, chapter).executeAsList() }
}

// GOOD: Map to domain model
class DatabaseVerseRepository(private val db: BibleDatabase) : VerseRepository {
    override suspend fun getVerses(
        bookId: Int,
        chapter: Int,
        language: Language
    ): List<Verse> = storageCall("Cannot read verses") {
        val rows = when (language) {
            Language.RU -> db.verseQueries.selectRussianVerses(bookId, chapter)
            Language.CS -> db.verseQueries.selectChurchSlavonicVerses(bookId, chapter)
            Language.EL -> db.verseQueries.selectGreekVerses(bookId, chapter)
        }
        rows.executeAsList().map { it.toDomainVerse() }
    }
}
```

---

## Presentation Layer

### ViewModel Discipline

ViewModels are **thin coordinators**. They receive events, call use cases, map results to UI state, and catch `StorageException` to show a general error. That's it. For a request with nothing to check and nothing to decide, a ViewModel calls a use case or the interface that the domain layer declares, as the Decisions Log of the project's implementation plan records. A ViewModel with an `if` or a `when` that decides something about the subject is a sign that business logic has leaked out of the domain layer.

### One ViewModel per Concern

Each independent concern gets its own ViewModel and state. Don't merge unrelated concerns into a single ViewModel just because they appear on the same screen. A "concern" is a cohesive group of state and behavior — reading Bible text is one concern, navigating books/chapters is another. Composables within a concern share the same ViewModel; they don't each need their own.

```kotlin
// BAD: God ViewModel that owns unrelated concerns
class MainViewModel(...) : ViewModel() {
    data class State(
        // Reading concern
        val book: Book? = null,
        val chapter: Int = 1,
        val verses: List<Verse> = emptyList(),
        // Navigation concern — independent state lifecycle
        val isDrawerOpen: Boolean = false,
        val groups: List<BookGroup> = emptyList(),
        val expandedBookId: Int? = null,
    )
    // 20 methods managing all of the above = god object
}

// GOOD: Separate ViewModels per concern, screen coordinates between them
class ReaderViewModel(private val getChapter: GetChapterUseCase) : ViewModel() {
    // Reading concern: book, chapter, language, verses, loading, error
}

class DrawerViewModel(private val getBookGroups: GetBookGroupsUseCase) : ViewModel() {
    // Navigation concern: groups, selected group, expanded book, open/closed
}

@Composable
fun BibleScreen(
    readerViewModel: ReaderViewModel,
    drawerViewModel: DrawerViewModel
) {
    val readerState by readerViewModel.state.collectAsState()
    val drawerState by drawerViewModel.state.collectAsState()

    // Screen wires cross-concern communication via callbacks
    DrawerPanel(
        state = drawerState,
        onEvent = drawerViewModel::onEvent,
        onChapterSelected = { bookId, chapter ->
            readerViewModel.onEvent(ReaderEvent.LoadChapter(bookId, chapter))
        }
    )
    ReaderContent(state = readerState, onEvent = readerViewModel::onEvent)
}
```

### Dumb UI Containers

Layout containers (drawers, bottom bars, app bars, sheets) are pure slots. They accept content as composable lambdas and know nothing about domain concepts.

```kotlin
// BAD: Container knows about domain
@Composable
fun AppDrawer(viewModel: DrawerViewModel) {
    val books = viewModel.books.collectAsState()
    ModalDrawerSheet {
        books.value.forEach { BookItem(it) }
    }
}

// GOOD: Container is a layout slot
@Composable
fun AppScaffold(
    drawerContent: @Composable () -> Unit,
    bottomBarContent: @Composable () -> Unit,
    content: @Composable () -> Unit
) {
    ModalNavigationDrawer(
        drawerContent = { ModalDrawerSheet { drawerContent() } }
    ) {
        Scaffold(bottomBar = { bottomBarContent() }) { content() }
    }
}
```

### Unidirectional Data Flow (UDF)

Events flow up from UI, state flows down from ViewModel. The state is an immutable data class, the events are a sealed interface, and the ViewModel processes events and emits state.

```kotlin
data class ReaderState(
    val book: Book? = null,
    val chapter: Int = 1,
    val language: Language = Language.RU,
    val verses: List<Verse> = emptyList(),
    val isLoading: Boolean = false,
    val error: String? = null
)

sealed interface ReaderEvent {
    data class LoadChapter(val bookId: Int, val chapter: Int) : ReaderEvent
    data class ChangeLanguage(val language: Language) : ReaderEvent
    data class ChangeChapter(val chapter: Int) : ReaderEvent
}

class ReaderViewModel(
    private val getChapterUseCase: GetChapterUseCase,
    private val dispatcher: CoroutineDispatcher
) : ScreenModel {

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
        screenModelScope.launchCatchingStorage(onStorageFailure = { showError("Could not load the chapter") }, context = dispatcher) {
            _state.update { it.copy(isLoading = true, error = null) }
            show(getChapterUseCase(bookId, chapter, _state.value.language))
        }
    }

    private fun show(result: GetChapterResult) = when (result) {
        is GetChapterResult.Verses -> _state.update { it.copy(verses = result.verses, isLoading = false) }
        is GetChapterResult.BookNotFound -> showError("Book not found")
        is GetChapterResult.ChapterOutOfRange -> showError("Chapter ${result.chapter} does not exist (max: ${result.chapterCount})")
    }

    private fun showError(message: String) = _state.update { it.copy(error = message, isLoading = false) }
}
```

### Compose Screen

Screen observes state and sends events. No business logic in Compose.

```kotlin
// BAD: Logic and data access in Compose
@Composable
fun ReaderScreen(db: BibleDatabase) {
    var verses by remember { mutableStateOf(emptyList<Verse>()) }
    LaunchedEffect(Unit) {
        verses = db.verseQueries.select(1, 1).executeAsList()
    }
}

// GOOD: Screen observes state, delegates events; ReaderContent is pure UI rendering from state
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

### Structured Controls vs LLM Parsing

Two approaches to capturing user input:

**Structured controls** (buttons, sliders, dropdowns, toggles, editable lists) — use when the input domain is known at design time. The control constrains valid inputs directly — no parsing needed, no ambiguity possible.

**LLM parsing** (natural language → structured data) — use when input is genuinely unstructured: external feedback, free-form documents, pasted third-party text.

Default to structured controls. Only reach for LLM parsing when you cannot define the input domain at design time.

#### Control selection

| Input type | Control |
|---|---|
| Enumerated choice | Buttons, dropdown, radio group |
| Bounded number | Slider, stepper, number field with bounds |
| Boolean | Toggle, checkbox |
| Collection | Editable list, chips |
| Bounded range | Dual-handle slider, two number fields |

When user intent maps to a known set of actions, capture it with a direct control. This eliminates ambiguity and removes the need for a parsing layer between user and system.

#### When LLM parsing is appropriate

- Importing external feedback (architect/builder/family reviews as pasted text)
- Analyzing free-form documents
- Processing pasted text from third parties
- Any input where the domain cannot be enumerated at design time

```kotlin
// BAD: "Open or closed kitchen?" as a text field —
// user types "open", "yes", "the first one", "doesn't matter"…
// now you need a parser to map free text to two known options,
// and that parser is fragile, slow and ambiguous.
TextField(
    value = answer,
    onValueChange = { answer = it },
    label = { Text("Open or closed kitchen?") }
)
val style = llmParser.parseKitchenStyle(answer)

// GOOD: Known options presented directly — no parsing, no LLM
Row {
    Button(onClick = { onEvent(SetKitchenStyle(OPEN)) }) { Text("Open") }
    Button(onClick = { onEvent(SetKitchenStyle(CLOSED)) }) { Text("Closed") }
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
    single<VerseRepository> { DatabaseVerseRepository(get()) }
    single<BookRepository> { DatabaseBookRepository(get<BibleDatabase>().bookQueries) }
    single<SearchRepository> { DatabaseSearchRepository(get()) }
    factory { GetChapterUseCase(get(), get()) }
    factory { SearchBibleUseCase(get()) }
    factory { GetBooksUseCase(get()) }
    factory { ReaderViewModel(get(), get()) }
    factory { SearchViewModel(get(), get()) }
    factory { BookListViewModel(get(), get()) }
}

// GOOD: Modular DI, with the feature modules aggregated in appModule
val coreModule = module {
    single { DatabaseDriverFactory(get()).createDriver() }
    single { BibleDatabase(get()) }
    single<CoroutineDispatcher>(named("io")) { Dispatchers.IO }
}

val readerModule = module {
    single<BookRepository> { DatabaseBookRepository(get<BibleDatabase>().bookQueries) }
    single<VerseRepository> { DatabaseVerseRepository(get()) }
    factory { GetChapterUseCase(get(), get()) }
    factory { ReaderViewModel(get(), get(named("io"))) }
}

val searchModule = module {
    single<SearchRepository> { DatabaseSearchRepository(get()) }
    factory { SearchBibleUseCase(get()) }
    factory { SearchViewModel(get(), get(named("io"))) }
}

val appModule = module {
    includes(coreModule, readerModule, searchModule)
}
```

### Scoping Rules

`single`: shared instances (repositories, database). `factory`: new instance per injection (use cases, ViewModels).

```kotlin
single<VerseRepository> { DatabaseVerseRepository(get()) }
factory { GetChapterUseCase(get(), get()) }
factory { ReaderViewModel(get(), get(named("io"))) }
```

---

## Error Handling

### Named Outcomes and Other Failures

When the requirements text of a use case names more than one outcome, the use case returns its own sealed type with one case per outcome; when it names one, it returns the value itself (see [Use Cases](#use-cases)). `kotlin.Result` is not used for outcomes, and no error type is shared by a whole feature. A repository answers "there is none" with `null`, and the use case turns it into its own named outcome. An outcome is never a generic `Exception` with a message, such as `Exception("Book not found")`: that is unstructured, and the caller would have to parse the string to tell the outcomes apart.

A failure that the text does not name (disk, database, network) is thrown. Code that calls a storage, network or platform library catches that library's own exception types only through one function, `storageCall`, never `Exception`, `Throwable` or `CancellationException`, and throws `StorageException`, which the domain layer declares, with the original as the cause. When common code cannot name the library's exception type, `storageCall` is an `expect` function: the repository passes its call to it as a lambda, and each `actual` runs the lambda in a `try`, catches that platform's exception type and throws `StorageException`. In a function that returns a `Flow`, the lambda holds the call that runs the query, not the call that builds the `Flow`. A use case does not catch it. The ViewModel that starts the use case catches it and shows a general error; all ViewModels do this through one function, so the `catch` is written once. `runCatching` is not used in `suspend` functions.

```kotlin
// BAD: one error type for the feature, returned in Result; runCatching in a suspend function would also catch CancellationException
sealed class ReaderError : Exception() {
    data class BookNotFound(val bookId: Int) : ReaderError()
}

interface BookRepository {
    suspend fun getBookById(bookId: Int): Result<Book>
}

class DatabaseBookRepository(private val bookQueries: BookQueries) : BookRepository {
    override suspend fun getBookById(bookId: Int): Result<Book> = runCatching {
        bookQueries.selectById(bookId).executeAsOneOrNull()?.toDomain() ?: throw ReaderError.BookNotFound(bookId)
    }
}

// GOOD: "there is none" is null; a database failure is thrown as StorageException with the original as its cause
// Domain layer
class StorageException(message: String, cause: Throwable) : Exception(message, cause)

// Data layer, commonMain
internal expect inline fun <T> storageCall(message: String, call: () -> T): T

class DatabaseBookRepository(private val bookQueries: BookQueries) : BookRepository {
    override suspend fun getBookById(bookId: Int): Book? = storageCall("Cannot read book $bookId") {
        bookQueries.selectById(bookId).executeAsOneOrNull()?.toDomain()
    }
}

// Data layer, androidMain
internal actual inline fun <T> storageCall(message: String, call: () -> T): T = try {
    call()
} catch (e: SQLiteException) {
    throw StorageException(message, e)
}

// Presentation layer: every ViewModel catches StorageException through this one function
fun CoroutineScope.launchCatchingStorage(
    onStorageFailure: () -> Unit,
    context: CoroutineContext = EmptyCoroutineContext,
    block: suspend CoroutineScope.() -> Unit
): Job = launch(context) {
    try {
        block()
    } catch (e: StorageException) {
        onStorageFailure()
    }
}
```

---

## Navigation

### Type-Safe Screen Definitions

Each screen is a Voyager Screen with its required parameters.

```kotlin
// BAD: String-based navigation with manual argument parsing
navigator.navigate("reader/$bookId/$chapter")

// GOOD: Type-safe screen objects; navigate with type safety by pushing one
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

navigator.push(ReaderScreen(bookId = 51, chapter = 1))
```

---

## Summary Checklist

### Architecture
- [ ] Three layers: Presentation -> Domain <- Data
- [ ] Domain is the stable center — depends on nothing
- [ ] Business logic lives in the domain layer (use cases and entities), not in ViewModels or repositories
- [ ] Repository interfaces in domain, implementations in data
- [ ] DB/API models mapped to domain models at repository boundary

### Domain
- [ ] A use case has its own input, output and rules; it is not a user action
- [ ] Use cases depend only on what the domain layer declares: entities and repository interfaces
- [ ] Use cases never depend on other use cases, ViewModels, or framework types
- [ ] Use cases are stateless (no mutable fields)
- [ ] A rule that is true of an entity whichever use case asks lives with the entity; application-specific rules live in use cases
- [ ] A use case whose requirements text names more than one outcome returns its own sealed type; no `kotlin.Result` for outcomes, no error type shared by a feature
- [ ] Code that calls a storage, network or platform library catches its exception types only through `storageCall` and throws `StorageException`; use cases do not catch it; no `runCatching` in `suspend` functions

### Presentation
- [ ] ViewModels are thin coordinators: no `if` or `when` that decides something about the subject
- [ ] ViewModels call use cases, map results to state, and catch `StorageException` — nothing more; a request with nothing to check and nothing to decide follows the choice recorded in the Decisions Log of the implementation plan
- [ ] One ViewModel per concern, not per screen
- [ ] UI containers are dumb layout slots — no domain awareness
- [ ] Immutable state data class
- [ ] Sealed event interface
- [ ] Unidirectional data flow (events up, state down)
- [ ] Compose screens have zero business logic

### Features
- [ ] Package by feature, layer within feature
- [ ] Koin module per feature

### DI
- [ ] All dependencies injected via constructor
- [ ] Dispatchers are injectable
- [ ] Repositories as single, use cases and ViewModels as factory
