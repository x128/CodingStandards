# Kotlin / KMP Coding Standards

## Table of Contents
1. [Naming](#naming)
2. [Functions](#functions)
3. [Classes](#classes)
4. [Null Safety](#null-safety)
5. [Error Handling](#error-handling)
6. [State Management](#state-management)
7. [Async & Concurrency](#async--concurrency)
8. [Collections](#collections)
9. [Comments & Documentation](#comments--documentation)
10. [Testing](#testing)

---

## Naming

### Variables

```kotlin
// BAD: Abbreviations, unclear meaning
val vidDur = 120
val t = System.currentTimeMillis()
val lst = mutableListOf<Track>()
val flag = true
val temp = calculateSomething()

// GOOD: Descriptive, self-documenting
val videoDurationSeconds = 120
val timestampMillis = System.currentTimeMillis()
val audioTracks = mutableListOf<Track>()
val isExportEnabled = true
val encodingBitrate = calculateOptimalBitrate()
```

### Booleans

```kotlin
// BAD: No verb prefix, ambiguous
val enabled: Boolean
val video: Boolean
val processing: Boolean
val check: Boolean

// GOOD: Clear intent with is/has/can/should
val isEnabled: Boolean
val hasVideo: Boolean
val isProcessing: Boolean
val shouldAutoSave: Boolean
val canUndo: Boolean
```

### Functions

```kotlin
// BAD: Noun names, unclear action
fun video(): Video
fun tracks(): List<Track>
fun validation(): Boolean
fun data()

// GOOD: Verb phrases describing action
fun loadVideo(): Video
fun fetchTracks(): List<Track>
fun validateFormat(): Boolean
fun exportData()

// BAD: Generic names
fun process(input: Any)
fun handle(event: Event)
fun doSomething()
fun execute()

// GOOD: Specific, action-oriented
fun encodeVideoToH264(video: RawVideo): EncodedVideo
fun handlePlaybackEvent(event: PlaybackEvent)
fun applyAudioNormalization(track: AudioTrack)
fun executeExportPipeline(project: Project)
```

### Constants

```kotlin
// BAD: Magic numbers, unclear purpose
val size = 1024 * 1024 * 50
val timeout = 30000
val ratio = 1.777778

// GOOD: Named constants with units
const val MEGABYTE = 1024 * 1024
const val MAX_VIDEO_SIZE_BYTES = 50 * MEGABYTE
val EXPORT_TIMEOUT = 30.seconds
const val WIDESCREEN_ASPECT_RATIO = 16.0 / 9.0
```

---

## Functions

### Single Responsibility

```kotlin
// BAD: Function doing multiple things
fun processVideoAndUpload(videoPath: String) {
    val video = File(videoPath).readBytes()
    val compressed = compressVideo(video)
    val encoded = encodeToH264(compressed)
    val thumbnail = extractThumbnail(encoded)
    saveThumbnail(thumbnail)
    val url = uploadToServer(encoded)
    saveUrlToDatabase(url)
    sendNotification("Upload complete")
}

// GOOD: Single responsibility, composable
fun compressVideo(video: ByteArray): ByteArray
fun encodeToH264(video: ByteArray): EncodedVideo
fun extractThumbnail(video: EncodedVideo): Thumbnail
fun uploadVideo(video: EncodedVideo): Url

// Compose in a use case
class ExportAndUploadUseCase(...) {
    suspend operator fun invoke(videoPath: String): Url {
        val video = loadVideo(videoPath)
        val compressed = compressVideo(video)
        val encoded = encodeToH264(compressed)
        return uploadVideo(encoded)
    }
}
```

### One Thing per Function

```kotlin
// BAD: Long function with multiple levels of abstraction
fun exportProject(project: Project): ExportResult {
    // validation...
    // video processing...
    // audio mixing...
    // encoding...
    // file writing...
    // cleanup...
    // all of them in this one function
}

// GOOD: Short functions, each doing one thing
fun exportProject(project: Project): ExportResult {
    validateProject(project)
    val videoTrack = processVideoTracks(project.videoTracks)
    val audioTrack = mixAudioTracks(project.audioTracks)
    val encoded = encodeMedia(videoTrack, audioTrack, project.settings)
    return writeToFile(encoded, project.outputPath)
}

private fun validateProject(project: Project) { /* validation */ }
private fun processVideoTracks(tracks: List<VideoTrack>): VideoTrack { /* video processing */ }
private fun mixAudioTracks(tracks: List<AudioTrack>): AudioTrack { /* audio mixing */ }
```

### Parameters

```kotlin
// BAD: Too many parameters
fun createVideo(
    title: String,
    description: String,
    duration: Int,
    width: Int,
    height: Int,
    fps: Int,
    codec: String,
    bitrate: Int,
    audioChannels: Int,
    sampleRate: Int
): Video

// GOOD: Use data classes for related parameters
data class VideoMetadata(
    val title: String,
    val description: String
)

data class VideoFormat(
    val width: Int,
    val height: Int,
    val fps: Int,
    val codec: Codec,
    val bitrate: Int
)

data class AudioFormat(
    val channels: Int,
    val sampleRate: Int
)

fun createVideo(
    metadata: VideoMetadata,
    videoFormat: VideoFormat,
    audioFormat: AudioFormat
): Video
```

### Avoid Deep Nesting

```kotlin
// BAD: Deep nesting, hard to follow
fun processMedia(file: File?): ProcessMediaResult {
    if (file != null) {
        if (file.exists()) {
            if (file.canRead()) {
                val content = file.readBytes()
                if (content.isNotEmpty()) {
                    if (isValidFormat(content)) {
                        return ProcessMediaResult.Parsed(parseMedia(content))
                    } else {
                        return ProcessMediaResult.InvalidFormat
                    }
                } else {
                    return ProcessMediaResult.EmptyFile
                }
            } else {
                return ProcessMediaResult.NoReadPermission
            }
        } else {
            return ProcessMediaResult.FileNotFound
        }
    } else {
        return ProcessMediaResult.NoFile
    }
}

// GOOD: Early returns, flat structure
fun processMedia(file: File?): ProcessMediaResult {
    if (file == null) return ProcessMediaResult.NoFile
    if (!file.exists()) return ProcessMediaResult.FileNotFound
    if (!file.canRead()) return ProcessMediaResult.NoReadPermission

    val content = file.readBytes()
    if (content.isEmpty()) return ProcessMediaResult.EmptyFile
    if (!isValidFormat(content)) return ProcessMediaResult.InvalidFormat

    return ProcessMediaResult.Parsed(parseMedia(content))
}
```

---

## Classes

### Single Responsibility

```kotlin
// BAD: God class doing everything
class VideoManager {
    fun loadVideo()
    fun saveVideo()
    fun encodeVideo()
    fun uploadVideo()
    fun downloadVideo()
    fun playVideo()
    fun pauseVideo()
    fun seekTo()
    fun extractThumbnail()
    fun applyFilter()
    fun trimVideo()
    fun mergeVideos()
    fun convertFormat()
    fun compressVideo()
    // ... 30 more methods
}

// GOOD: Separate classes by responsibility
class VideoLoader(private val fileSystem: FileSystem)
class VideoEncoder(private val codecFactory: CodecFactory)
class VideoUploader(private val apiClient: ApiClient)
class VideoPlayer(private val mediaPlayer: MediaPlayer)
class VideoEditor(private val processor: VideoProcessor)
```

### Immutability

```kotlin
// BAD: Mutable state exposed
class ProjectState {
    var currentVideo: Video? = null
    var tracks = mutableListOf<Track>()
    var isPlaying = false
    var volume = 1.0f

    fun addTrack(track: Track) {
        tracks.add(track)
    }
}

// GOOD: Immutable data class, updated via copy
data class ProjectState(
    val currentVideo: Video? = null,
    val tracks: List<Track> = emptyList(),
    val isPlaying: Boolean = false,
    val volume: Float = 1.0f
)

val newState = state.copy(
    tracks = state.tracks + newTrack,
    isPlaying = true
)
```

### Dependency Injection

```kotlin
// BAD: Creating dependencies internally; a test cannot replace them, and the database is a singleton
class VideoRepository {
    private val api = VideoApi()
    private val cache = DiskCache()
    private val database = VideoDatabase.getInstance()

    fun loadVideo(id: String): Video {
        return cache.get(id) ?: api.fetch(id).also { cache.put(id, it) }
    }
}

// GOOD: Dependencies injected via constructor
class VideoRepository(
    private val api: VideoApi,
    private val cache: Cache<String, Video>,
    private val database: VideoDatabase
) {
    fun loadVideo(id: String): Video {
        return cache.get(id) ?: api.fetch(id).also { cache.put(id, it) }
    }
}
```

### Interface Segregation

```kotlin
// BAD: Fat interface
interface MediaHandler {
    fun loadVideo(path: String): Video
    fun loadAudio(path: String): Audio
    fun loadImage(path: String): Image
    fun saveVideo(video: Video, path: String)
    fun saveAudio(audio: Audio, path: String)
    fun saveImage(image: Image, path: String)
    fun encodeVideo(video: Video): ByteArray
    fun decodeVideo(data: ByteArray): Video
    fun streamVideo(url: String): Flow<VideoFrame>
    fun uploadVideo(video: Video): Url
}

// GOOD: Segregated interfaces
interface VideoLoader {
    fun load(path: String): Video
}

interface VideoSaver {
    fun save(video: Video, path: String)
}

interface VideoEncoder {
    fun encode(video: Video): ByteArray
    fun decode(data: ByteArray): Video
}

interface VideoStreamer {
    fun stream(url: String): Flow<VideoFrame>
}
```

---

## Null Safety

### Never Use !!

```kotlin
// BAD: Force unwrap crashes at runtime
fun getVideoDuration(video: Video?): Int {
    return video!!.duration!!
}

// BAD: Assuming non-null after check in different scope; another thread can set cachedVideo to null in between, and then `!!` crashes
var cachedVideo: Video? = null

fun processVideo() {
    if (cachedVideo != null) {
        println(cachedVideo!!.title)
    }
}

// GOOD: Safe handling with let/elvis
fun getVideoDuration(video: Video?): Int? {
    return video?.duration
}

fun getVideoDurationOrDefault(video: Video?): Int {
    return video?.duration ?: 0
}

// GOOD: Smart cast with local val; safe, because no other thread can change a local val
fun processVideo() {
    val video = cachedVideo ?: return
    println(video.title)
}
```

### Meaningful Null Handling

```kotlin
// BAD: Swallowing nulls silently; the Video.empty() fallback hides problems
fun loadUserVideo(): Video {
    val user = getUser()
    val videoId = user?.lastVideoId
    val video = videoId?.let { loadVideo(it) }
    return video ?: Video.empty()
}

// GOOD: Each null becomes a named outcome
fun loadUserVideo(): LoadUserVideoResult {
    val user = getUser() ?: return LoadUserVideoResult.UserNotLoggedIn
    val videoId = user.lastVideoId ?: return LoadUserVideoResult.NoVideoSelected
    return LoadUserVideoResult.Loaded(loadVideo(videoId))
}
```

### Nullable Collections

```kotlin
// BAD: Nullable collection; callers must handle null AND empty
fun getTracks(): List<Track>? {
    return tracks.takeIf { it.isNotEmpty() }
}

// GOOD: Return empty collection instead of null
fun getTracks(): List<Track> {
    return tracks.toList()
}
```

---

## Error Handling

### Return Named Outcomes, Not `Result`

An outcome that the requirements name is returned, not thrown. When the requirements name more than one outcome, the use case returns its own sealed type with one case per outcome. When they name one, it returns the value itself. `kotlin.Result` is not used for outcomes, and a feature has no shared error type. A refusal that a rule of an entity gives is declared with that rule, and each use case carries it in one case (ARCHITECTURE.md, "Use Cases"). A repository answers "there is none" with `null`; the use case turns it into its own named outcome.

A failure that the requirements do not name (disk, database, network) is thrown as a `StorageException`. The use case does not catch it. The ViewModel that starts the use case catches it and shows a general error; all ViewModels do this through one function, so the `catch` is written once.

```kotlin
// BAD: Exceptions for expected failures
fun loadVideo(id: String): Video {
    val video = database.findById(id)
    if (video == null) throw VideoNotFoundException(id)
    if (video.isCorrupted) throw CorruptedVideoException(id)
    return video
}

// BAD: The caller has no idea what to catch, so it also catches Exception for whatever else could happen
fun caller() {
    try {
        val video = loadVideo(id)
    } catch (e: VideoNotFoundException) {
        // ...
    } catch (e: CorruptedVideoException) {
        // ...
    } catch (e: Exception) {
        // ...
    }
}

// GOOD: loadVideo returns its expected failures as cases; the caller handles each one
sealed interface LoadVideoResult {
    data class Loaded(val video: Video) : LoadVideoResult
    data class NotFound(val id: String) : LoadVideoResult
    data class Corrupted(val id: String) : LoadVideoResult
}

fun loadVideo(id: String): LoadVideoResult {
    val video = database.findById(id) ?: return LoadVideoResult.NotFound(id)
    if (video.isCorrupted) return LoadVideoResult.Corrupted(id)
    return LoadVideoResult.Loaded(video)
}

fun caller() {
    when (val result = loadVideo(id)) {
        is LoadVideoResult.Loaded -> displayVideo(result.video)
        is LoadVideoResult.NotFound -> showNotFoundMessage()
        is LoadVideoResult.Corrupted -> offerRecoveryOptions()
    }
}

// BAD: The signature names no outcome; ReaderError is one error type shared by the feature
class GetChapterUseCase(
    private val bookRepository: BookRepository,
    private val verseRepository: VerseRepository
) {
    suspend operator fun invoke(bookId: Int, chapter: Int, language: Language): Result<List<Verse>> {
        val book = bookRepository.getBookById(bookId)
            ?: return Result.failure(ReaderError.BookNotFound(bookId))
        if (!book.hasChapter(chapter)) return Result.failure(ReaderError.ChapterOutOfRange(chapter))
        return Result.success(verseRepository.getVerses(bookId, chapter, language))
    }
}

// GOOD: One case per named outcome; the caller handles every case
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

// GOOD: Every ViewModel catches StorageException through this one function
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

class ReaderViewModel(private val getChapter: GetChapterUseCase) : ViewModel() {
    fun loadChapter(bookId: Int, chapter: Int, language: Language) {
        viewModelScope.launchCatchingStorage(onStorageFailure = ::showGeneralError) {
            when (val result = getChapter(bookId, chapter, language)) {
                is GetChapterResult.Verses -> showVerses(result.verses)
                is GetChapterResult.BookNotFound -> showBookNotFound()
                is GetChapterResult.ChapterOutOfRange -> showChapterOutOfRange(result.chapterCount)
            }
        }
    }
}
```

### Don't Catch Generic Exceptions

Code that calls a storage, network or platform library catches only the exception types of that library, and only through one function, `storageCall`: never `Exception` or `Throwable`, and never `CancellationException`. It throws `StorageException`, a type that the domain layer declares, with the original as the cause. `runCatching` is not used in `suspend` functions: it catches `CancellationException` too. Programming errors such as `NullPointerException` or `IndexOutOfBoundsException` are not caught: they are bugs, and they crash. When common code of a multiplatform project cannot name the library's exception type, `storageCall` is an `expect` function with an `actual` on each platform (ARCHITECTURE.md, "Named Outcomes and Other Failures").

```kotlin
// BAD: Catching everything, bugs and CancellationException too; a database failure reads as "no book"
class DatabaseBookRepository(private val bookQueries: BookQueries) : BookRepository {
    override suspend fun getBookById(bookId: Int): Book? = try {
        bookQueries.selectById(bookId).executeAsOneOrNull()?.toDomain()
    } catch (e: Exception) {
        null
    }
}

// BAD: runCatching in a suspend function does the same
class DatabaseBookRepository(private val bookQueries: BookQueries) : BookRepository {
    override suspend fun getBookById(bookId: Int): Book? =
        runCatching { bookQueries.selectById(bookId).executeAsOneOrNull()?.toDomain() }.getOrNull()
}

// GOOD: One function catches the library's own exception type and throws StorageException with it as the cause
inline fun <T> storageCall(message: String, call: () -> T): T = try {
    call()
} catch (e: SQLiteException) {
    throw StorageException(message, e)
}

class DatabaseBookRepository(private val bookQueries: BookQueries) : BookRepository {
    override suspend fun getBookById(bookId: Int): Book? = storageCall("Cannot read book $bookId") {
        bookQueries.selectById(bookId).executeAsOneOrNull()?.toDomain()
    }
}
```

---

## State Management

### Immutable UI State

```kotlin
// BAD: Mutable state with multiple sources of truth; nothing tells the UI about a change
class EditorViewModel : ViewModel() {
    var currentVideo: Video? = null
    var isPlaying = false
    var progress = 0f
    var error: String? = null

    fun play() {
        isPlaying = true
    }
}

// GOOD: Single immutable state flow
data class EditorState(
    val video: Video? = null,
    val playbackState: PlaybackState = PlaybackState.Idle,
    val progress: Float = 0f,
    val error: UiError? = null
)

sealed interface PlaybackState {
    data object Idle : PlaybackState
    data object Playing : PlaybackState
    data object Paused : PlaybackState
    data class Buffering(val percent: Int) : PlaybackState
}

class EditorViewModel(...) : ViewModel() {
    private val _state = MutableStateFlow(EditorState())
    val state: StateFlow<EditorState> = _state.asStateFlow()

    fun play() {
        _state.update { it.copy(playbackState = PlaybackState.Playing) }
    }
}
```

### Unidirectional Data Flow

```kotlin
// BAD: Two-way data binding, state scattered
class EditorScreen {
    fun onPlayClicked() {
        viewModel.isPlaying = true
        playButton.setIcon(pauseIcon)
        updateProgressBar()
    }
}

// GOOD: Events flow up, state flows down
// ViewModel
sealed interface EditorEvent {
    data object PlayClicked : EditorEvent
    data object PauseClicked : EditorEvent
    data class SeekTo(val position: Float) : EditorEvent
}

class EditorViewModel(...) {
    fun onEvent(event: EditorEvent) {
        when (event) {
            EditorEvent.PlayClicked -> play()
            EditorEvent.PauseClicked -> pause()
            is EditorEvent.SeekTo -> seekTo(event.position)
        }
    }
}

// UI (Compose)
@Composable
fun EditorScreen(viewModel: EditorViewModel) {
    val state by viewModel.state.collectAsState()

    PlaybackControls(
        isPlaying = state.playbackState == PlaybackState.Playing,
        onPlayClick = { viewModel.onEvent(EditorEvent.PlayClicked) },
        onPauseClick = { viewModel.onEvent(EditorEvent.PauseClicked) }
    )
}
```

---

## Async & Concurrency

### Structured Concurrency

```kotlin
// BAD: GlobalScope, no cancellation support
fun loadAllMedia() {
    GlobalScope.launch {
        val videos = loadVideos()
        val images = loadImages()
    }
}

// BAD: Fire and forget
fun saveProject(project: Project) {
    CoroutineScope(Dispatchers.IO).launch {
        repository.save(project)
    }
}

// GOOD: Structured concurrency with proper scope: launchCatchingStorage (Error Handling) launches in viewModelScope; videos and images load in parallel
class MediaViewModel(
    private val loadVideosUseCase: LoadVideosUseCase,
    private val loadImagesUseCase: LoadImagesUseCase
) : ViewModel() {

    fun loadAllMedia() {
        viewModelScope.launchCatchingStorage(onStorageFailure = { _state.update { it.copy(error = UiError.General) } }) {
            coroutineScope {
                val videosDeferred = async { loadVideosUseCase() }
                val imagesDeferred = async { loadImagesUseCase() }

                val videos = videosDeferred.await()
                val images = imagesDeferred.await()

                _state.update { it.copy(videos = videos, images = images) }
            }
        }
    }
}
```

### Dispatcher Usage

```kotlin
// BAD: Blocking main thread; heavyProcessing blocks the calling thread
class VideoProcessor {
    fun processVideo(video: Video): ProcessedVideo {
        return heavyProcessing(video)
    }
}

// BAD: Hardcoded dispatcher; a test cannot replace it
class VideoProcessor {
    suspend fun processVideo(video: Video): ProcessedVideo {
        return withContext(Dispatchers.Default) {
            heavyProcessing(video)
        }
    }
}

// GOOD: Injected dispatcher
class VideoProcessor(
    private val processingDispatcher: CoroutineDispatcher = Dispatchers.Default
) {
    suspend fun processVideo(video: Video): ProcessedVideo {
        return withContext(processingDispatcher) {
            heavyProcessing(video)
        }
    }
}

// GOOD: A test passes its own dispatcher
val testDispatcher = StandardTestDispatcher()
val processor = VideoProcessor(testDispatcher)
```

### Flow Best Practices

```kotlin
// BAD: Not handling backpressure; it can overwhelm consumers
fun observeFrames(): Flow<Frame> = flow {
    while (true) {
        emit(captureFrame())
    }
}

// BAD: Collecting multiple flows separately
viewModelScope.launch { flow1.collect { handleFlow1(it) } }
viewModelScope.launch { flow2.collect { handleFlow2(it) } }

// GOOD: Conflate for UI, buffer for processing; conflate drops intermediate frames if the consumer is slow
fun observeFrames(): Flow<Frame> = flow {
    while (currentCoroutineContext().isActive) {
        emit(captureFrame())
    }
}.conflate()

// GOOD: Combine related flows
combine(
    playbackStateFlow,
    progressFlow,
    volumeFlow
) { playback, progress, volume ->
    PlayerState(playback, progress, volume)
}.collect { state ->
    updateUI(state)
}
```

---

## Collections

### Prefer Immutable

```kotlin
// BAD: Exposing mutable collections; external code can modify them
class Playlist {
    val tracks = mutableListOf<Track>()
}

// GOOD: Expose immutable, mutate internally
class Playlist {
    private val _tracks = mutableListOf<Track>()
    val tracks: List<Track> get() = _tracks.toList()

    fun addTrack(track: Track) {
        _tracks.add(track)
    }
}

// BETTER: Fully immutable with copy
data class Playlist(
    val tracks: List<Track> = emptyList()
) {
    fun withTrack(track: Track) = copy(tracks = tracks + track)
    fun withoutTrack(track: Track) = copy(tracks = tracks - track)
}
```

### Functional Operations

```kotlin
// BAD: Imperative loops with mutation
fun getActiveVideoTracks(project: Project): List<VideoTrack> {
    val result = mutableListOf<VideoTrack>()
    for (track in project.tracks) {
        if (track is VideoTrack) {
            if (track.isEnabled) {
                if (!track.isEmpty()) {
                    result.add(track)
                }
            }
        }
    }
    return result
}

// GOOD: Functional chain
fun getActiveVideoTracks(project: Project): List<VideoTrack> =
    project.tracks
        .filterIsInstance<VideoTrack>()
        .filter { it.isEnabled }
        .filterNot { it.isEmpty() }
```

### Avoid Unnecessary Allocations

```kotlin
// BAD: Multiple intermediate collections: map creates a List, filter another List, toSet a Set
fun processIds(items: List<Item>): Set<String> {
    return items
        .map { it.id }
        .filter { it.isNotEmpty() }
        .toSet()
}

// GOOD: Use sequences for large collections
fun processIds(items: List<Item>): Set<String> {
    return items.asSequence()
        .map { it.id }
        .filter { it.isNotEmpty() }
        .toSet()
}

// GOOD: Or combine operations
fun processIds(items: List<Item>): Set<String> {
    return items.mapNotNullTo(mutableSetOf()) { item ->
        item.id.takeIf { it.isNotEmpty() }
    }
}
```

---

## Comments & Documentation

The rule is the "Comments" section of [CLEAN_CODE.md](CLEAN_CODE.md#comments): no comments and no KDoc, except the test markers (`// Arrange`, `// Act`, `// Assert`, or `// Given`, `// When`, `// Then`) and the kinds that the Decisions Log of the implementation plan allows. An existing comment is never just deleted: a reason, a warning, a unit, an outside source or a promise first moves into a name, a type or a check in the code, pinned by a test, and the number of a rule of the project's requirements into the test name; work to do goes to the tracker, history to the commit message. This section shows the Kotlin forms.

### A Name, a Type or a Check Instead of a Comment

```kotlin
// BAD: comments say what the code, a name or a check can say
// Loop through all tracks and find video tracks that are enabled
for (track in tracks) {
    if (track is VideoTrack && track.isEnabled) {
        // Add to result list
        result.add(track)
    }
}

// Volume must be between 0 and 1
fun withVolume(state: ProjectState, volume: Float) = state.copy(volume = volume)

// Max duration in hours
val max = 4

// GOOD: the code says it
val enabledVideoTracks = tracks
    .filterIsInstance<VideoTrack>()
    .filter { it.isEnabled }

fun withVolume(state: ProjectState, volume: Float): ProjectState {
    require(volume in 0f..1f) { "Volume $volume is outside 0..1" }
    return state.copy(volume = volume)
}

val MAX_EXPORT_DURATION = 4.hours
```

### A Name and a Test Instead of a Reason or a KDoc

```kotlin
// BAD: the reason is a comment that nothing checks
// Platform limitation: iOS AVFoundation crashes with videos > 4 hours
if (duration > MAX_EXPORT_DURATION) {
    duration = MAX_EXPORT_DURATION
}

// BAD: the KDoc states a precondition, an option set, a completion promise and a failure, and nothing checks them
interface ProjectExporter {
    /**
     * Exports a project to a video file.
     *
     * @param project The project to export. Must have at least one video track.
     * @param options Export configuration including format, quality, and output path.
     * @return A flow that emits progress updates. Completes when export finishes.
     *         Throws [InsufficientStorageException] if disk space runs out.
     * @throws IllegalArgumentException if project has no video tracks.
     */
    fun export(project: Project, options: ExportOptions): Flow<ExportProgress>
}

// GOOD: the purpose and the limit are names, the options and the precondition are types; completing and throwing StorageException are what every flow of the project does (ARCHITECTURE.md), pinned by tests that fail when one is broken, and the test of the limit gives its reason
val LONGEST_VIDEO_AVFOUNDATION_EXPORTS = 4.hours

duration = duration.coerceAtMost(LONGEST_VIDEO_AVFOUNDATION_EXPORTS)

data class ExportOptions(val format: VideoFormat, val quality: Quality, val outputPath: Path)

class ProjectWithVideo(val project: Project) {
    init {
        require(project.videoTracks.isNotEmpty()) { "A project to export needs a video track" }
    }
}

interface ProjectExporter {
    fun exportToVideoFile(project: ProjectWithVideo, options: ExportOptions): Flow<ExportProgress>
}

@Test
fun `export truncates a video longer than 4 hours to 4 hours because iOS AVFoundation crashes on longer videos`() = runTest {
    // Arrange
    // Act
    exporter.exportToVideoFile(projectLasting(4.hours + 1.seconds), options).toList()

    // Assert
    assertEquals(LONGEST_VIDEO_AVFOUNDATION_EXPORTS, videoDuration(options.outputPath))
}

@Test
fun `a project without a video track cannot be exported`() {
    // Arrange
    val project = projectWithoutVideoTracks()

    // Act
    val failure = assertFails { ProjectWithVideo(project) }

    // Assert
    assertIs<IllegalArgumentException>(failure)
}

@Test
fun `export flow completes after the video file is written`() = runTest {
    // Arrange
    // Act
    val progress = exporter.exportToVideoFile(projectLasting(1.minutes), options).toList()

    // Assert
    assertEquals(ExportProgress.Done, progress.last())
    assertTrue(options.outputPath.toFile().exists())
}

@Test
fun `export throws StorageException when the disk runs out of space`() = runTest {
    // Arrange
    // Act
    val failure = assertFails { exporter.exportToVideoFile(projectLasting(1.minutes), fullDiskOptions).toList() }

    // Assert
    assertIs<StorageException>(failure)
}
```

### No Commented-Out Code

```kotlin
// BAD: Dead code left in comments
fun processVideo(video: Video): Video {
    // val oldResult = legacyProcess(video)
    // if (oldResult.isValid) {
    //     return oldResult
    // }
    return newProcess(video)
}

// GOOD: Delete unused code; the commit message that deletes it says what it did
fun processVideo(video: Video) = newProcess(video)
```

---

## Testing

### Test Naming

```kotlin
// BAD: Vague test names
@Test
fun testExport()

@Test
fun videoTest()

@Test
fun test1()

// GOOD: Descriptive, documents behavior
@Test
fun `export fails with clear error when project has no tracks`()

@Test
fun `video duration is calculated correctly for variable frame rate content`()

@Test
fun `undo restores previous state after track deletion`()
```

### Test Structure (AAA)

```kotlin
// BAD: Mixed arrangement, action, assertion
@Test
fun `test video loading`() {
    val loader = VideoLoader(mockFileSystem)
    val result = loader.load("test.mp4")
    assertEquals(1920, result?.width)
    val anotherResult = loader.load("test2.mp4")
    assertTrue(anotherResult?.isValid == true)
    whenever(mockFileSystem.exists(any())).thenReturn(false)
    val failResult = loader.load("missing.mp4")
    assertNull(failResult)
}

// GOOD: Clear AAA structure, one assertion focus
@Test
fun `load returns video with correct dimensions`() {
    // Arrange
    val mockFile = createMockVideoFile(width = 1920, height = 1080)
    val loader = VideoLoader(mockFileSystem)

    // Act
    val video = loader.load(mockFile.path)

    // Assert
    assertEquals(1920, video?.width)
    assertEquals(1080, video?.height)
}

@Test
fun `load returns null when file does not exist`() {
    // Arrange
    whenever(mockFileSystem.exists(any())).thenReturn(false)
    val loader = VideoLoader(mockFileSystem)

    // Act
    val video = loader.load("missing.mp4")

    // Assert
    assertNull(video)
}
```

### Test Independence

```kotlin
// BAD: Tests depend on each other or shared mutable state; `test process` depends on `test load` running first
class VideoTests {
    companion object {
        var sharedVideo: Video? = null
    }

    @Test
    fun `test load`() {
        sharedVideo = loadVideo("test.mp4")
        assertNotNull(sharedVideo)
    }

    @Test
    fun `test process`() {
        val result = process(sharedVideo!!)
        assertTrue(result.isValid)
    }
}

// GOOD: Each test is independent and creates its own fresh test data
class VideoTests {
    private lateinit var loader: VideoLoader

    @BeforeEach
    fun setup() {
        loader = VideoLoader(FakeFileSystem())
    }

    @Test
    fun `load returns valid video`() {
        // Arrange
        // Act
        val video = loader.load("test.mp4")

        // Assert
        assertNotNull(video)
    }

    @Test
    fun `process transforms video correctly`() {
        // Arrange
        val video = createTestVideo()

        // Act
        val result = process(video)

        // Assert
        assertTrue(result.isValid)
    }
}
```

---

## Summary Checklist

Before committing code, verify:

### Naming
- [ ] Variables describe their content
- [ ] Functions describe their action
- [ ] Booleans have verb prefixes (is/has/can/should)
- [ ] No abbreviations or single-letter names (except `i` in loops, `it` in lambdas)

### Functions
- [ ] Each function does one thing
- [ ] CRAP score 8 or below, or a recorded exception (see CLEAN_CODE.md, "One Thing per Function")
- [ ] Max 3 parameters (use data class for more)
- [ ] Max 3 nesting levels

### Classes
- [ ] Single responsibility
- [ ] Dependencies injected via constructor
- [ ] State is immutable where possible
- [ ] One reason to change; its fields are used by most of its functions

### Safety
- [ ] No `!!` operators
- [ ] No mutable public properties
- [ ] Named outcomes are returned: the use case's own sealed type, or the value itself when there is one outcome; no `kotlin.Result` for outcomes
- [ ] No generic exception catching: never `Exception` or `Throwable`
- [ ] A repository implementation catches only its library's exception types, never `Exception`, `Throwable` or `CancellationException`, and throws `StorageException`
- [ ] Only the ViewModel that starts the use case catches `StorageException`; no `runCatching` in `suspend` functions

### Async
- [ ] Uses structured concurrency
- [ ] No GlobalScope
- [ ] Dispatchers are injectable

### Tests
- [ ] Descriptive names
- [ ] Independent (no shared mutable state)
- [ ] Clear AAA structure
