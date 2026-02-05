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
const val MAX_VIDEO_SIZE_BYTES = 50 * 1024 * 1024  // 50 MB
const val EXPORT_TIMEOUT_MILLIS = 30_000L          // 30 seconds
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
    suspend operator fun invoke(videoPath: String): Result<ExportResult> {
        return loadVideo(videoPath)
            .mapCatching { compressVideo(it) }
            .mapCatching { encodeToH264(it) }
            .mapCatching { uploadVideo(it) }
    }
}
```

### Function Length

```kotlin
// BAD: Long function with multiple levels of abstraction
fun exportProject(project: Project): ExportResult {
    // 15 lines of validation...
    // 20 lines of video processing...
    // 15 lines of audio mixing...
    // 10 lines of encoding...
    // 10 lines of file writing...
    // 10 lines of cleanup...
    // Total: 80+ lines
}

// GOOD: Short functions, each doing one thing
fun exportProject(project: Project): ExportResult {
    validateProject(project)
    val videoTrack = processVideoTracks(project.videoTracks)
    val audioTrack = mixAudioTracks(project.audioTracks)
    val encoded = encodeMedia(videoTrack, audioTrack, project.settings)
    return writeToFile(encoded, project.outputPath)
}

private fun validateProject(project: Project) { /* 10 lines */ }
private fun processVideoTracks(tracks: List<VideoTrack>): VideoTrack { /* 15 lines */ }
private fun mixAudioTracks(tracks: List<AudioTrack>): AudioTrack { /* 15 lines */ }
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
fun processMedia(file: File?): Result<Media> {
    if (file != null) {
        if (file.exists()) {
            if (file.canRead()) {
                val content = file.readBytes()
                if (content.isNotEmpty()) {
                    if (isValidFormat(content)) {
                        return Result.success(parseMedia(content))
                    } else {
                        return Result.failure(InvalidFormatError())
                    }
                } else {
                    return Result.failure(EmptyFileError())
                }
            } else {
                return Result.failure(ReadPermissionError())
            }
        } else {
            return Result.failure(FileNotFoundError())
        }
    } else {
        return Result.failure(NullFileError())
    }
}

// GOOD: Early returns, flat structure
fun processMedia(file: File?): Result<Media> {
    if (file == null) return Result.failure(NullFileError())
    if (!file.exists()) return Result.failure(FileNotFoundError())
    if (!file.canRead()) return Result.failure(ReadPermissionError())

    val content = file.readBytes()
    if (content.isEmpty()) return Result.failure(EmptyFileError())
    if (!isValidFormat(content)) return Result.failure(InvalidFormatError())

    return Result.success(parseMedia(content))
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

// GOOD: Immutable data class with copy
data class ProjectState(
    val currentVideo: Video? = null,
    val tracks: List<Track> = emptyList(),
    val isPlaying: Boolean = false,
    val volume: Float = 1.0f
)

// Update via copy
val newState = state.copy(
    tracks = state.tracks + newTrack,
    isPlaying = true
)
```

### Dependency Injection

```kotlin
// BAD: Creating dependencies internally
class VideoRepository {
    private val api = VideoApi()  // Hard to test
    private val cache = DiskCache()  // Hard to test
    private val database = VideoDatabase.getInstance()  // Singleton

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

// BAD: Assuming non-null after check in different scope
var cachedVideo: Video? = null

fun processVideo() {
    if (cachedVideo != null) {
        // Another thread could set cachedVideo to null here
        println(cachedVideo!!.title)  // Potential crash
    }
}

// GOOD: Safe handling with let/elvis
fun getVideoDuration(video: Video?): Int? {
    return video?.duration
}

fun getVideoDurationOrDefault(video: Video?): Int {
    return video?.duration ?: 0
}

// GOOD: Smart cast with local val
fun processVideo() {
    val video = cachedVideo ?: return
    println(video.title)  // Smart cast, safe
}
```

### Meaningful Null Handling

```kotlin
// BAD: Swallowing nulls silently
fun loadUserVideo(): Video {
    val user = getUser()
    val videoId = user?.lastVideoId
    val video = videoId?.let { loadVideo(it) }
    return video ?: Video.empty()  // Silent fallback hides problems
}

// GOOD: Explicit error handling
fun loadUserVideo(): Result<Video> {
    val user = getUser() ?: return Result.failure(UserNotLoggedInError())
    val videoId = user.lastVideoId ?: return Result.failure(NoVideoSelectedError())
    return loadVideo(videoId)
}
```

### Nullable Collections

```kotlin
// BAD: Nullable collection
fun getTracks(): List<Track>? {
    // Now callers must handle null AND empty
}

// GOOD: Return empty collection instead of null
fun getTracks(): List<Track> {
    return tracks.toList()  // Returns empty list if no tracks
}
```

---

## Error Handling

### Use Result Type

```kotlin
// BAD: Exceptions for expected failures
fun loadVideo(id: String): Video {
    val video = database.findById(id)
    if (video == null) throw VideoNotFoundException(id)  // Expected case
    if (video.isCorrupted) throw CorruptedVideoException(id)  // Expected case
    return video
}

// Caller has no idea what to catch
fun caller() {
    try {
        val video = loadVideo(id)
    } catch (e: VideoNotFoundException) {
        // ...
    } catch (e: CorruptedVideoException) {
        // ...
    } catch (e: Exception) {
        // What else could happen?
    }
}

// GOOD: Result type with sealed errors
sealed class VideoError {
    data class NotFound(val id: String) : VideoError()
    data class Corrupted(val id: String) : VideoError()
    data class StorageFull(val required: Long, val available: Long) : VideoError()
}

fun loadVideo(id: String): Result<Video, VideoError> {
    val video = database.findById(id)
        ?: return Result.failure(VideoError.NotFound(id))
    if (video.isCorrupted)
        return Result.failure(VideoError.Corrupted(id))
    return Result.success(video)
}

// Caller handles all cases explicitly
fun caller() {
    loadVideo(id)
        .onSuccess { video -> displayVideo(video) }
        .onFailure { error ->
            when (error) {
                is VideoError.NotFound -> showNotFoundMessage()
                is VideoError.Corrupted -> offerRecoveryOptions()
                is VideoError.StorageFull -> showStorageWarning(error.required)
            }
        }
}
```

### Don't Catch Generic Exceptions

```kotlin
// BAD: Catching everything
fun processVideo(path: String): Video? {
    return try {
        loadAndProcess(path)
    } catch (e: Exception) {
        null  // Swallows ALL errors including bugs
    }
}

// GOOD: Catch specific exceptions
fun processVideo(path: String): Result<Video> {
    return try {
        Result.success(loadAndProcess(path))
    } catch (e: IOException) {
        Result.failure(FileAccessError(path, e))
    } catch (e: CodecException) {
        Result.failure(EncodingError(e.message))
    }
    // Let programming errors (NPE, IndexOutOfBounds) crash - they're bugs
}
```

---

## State Management

### Immutable UI State

```kotlin
// BAD: Mutable state with multiple sources of truth
class EditorViewModel : ViewModel() {
    var currentVideo: Video? = null
    var isPlaying = false
    var progress = 0f
    var error: String? = null

    fun play() {
        isPlaying = true  // Who updates the UI?
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

// GOOD: Structured concurrency with proper scope
class MediaViewModel(
    private val loadVideosUseCase: LoadVideosUseCase,
    private val loadImagesUseCase: LoadImagesUseCase
) : ViewModel() {

    fun loadAllMedia() {
        viewModelScope.launch {
            // Parallel loading with structured concurrency
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
// BAD: Blocking main thread
class VideoProcessor {
    fun processVideo(video: Video): ProcessedVideo {
        return heavyProcessing(video)  // Blocks calling thread
    }
}

// BAD: Hardcoded dispatcher
class VideoProcessor {
    suspend fun processVideo(video: Video): ProcessedVideo {
        return withContext(Dispatchers.Default) {  // Not testable
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

// In tests:
val testDispatcher = StandardTestDispatcher()
val processor = VideoProcessor(testDispatcher)
```

### Flow Best Practices

```kotlin
// BAD: Not handling backpressure
fun observeFrames(): Flow<Frame> = flow {
    while (true) {
        emit(captureFrame())  // Can overwhelm consumers
    }
}

// BAD: Collecting multiple flows separately
viewModelScope.launch { flow1.collect { handleFlow1(it) } }
viewModelScope.launch { flow2.collect { handleFlow2(it) } }

// GOOD: Conflate for UI, buffer for processing
fun observeFrames(): Flow<Frame> = flow {
    while (currentCoroutineContext().isActive) {
        emit(captureFrame())
    }
}.conflate()  // Drop intermediate frames if consumer is slow

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
// BAD: Exposing mutable collections
class Playlist {
    val tracks = mutableListOf<Track>()  // External code can modify
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
// BAD: Multiple intermediate collections
fun processIds(items: List<Item>): Set<String> {
    return items
        .map { it.id }          // Creates List
        .filter { it.isNotEmpty() }  // Creates another List
        .toSet()                // Creates Set
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

### Code Should Be Self-Documenting

```kotlin
// BAD: Comment explains what code does (redundant)
// Loop through all tracks and find video tracks that are enabled
for (track in tracks) {
    if (track is VideoTrack && track.isEnabled) {
        // Add to result list
        result.add(track)
    }
}

// GOOD: Code is clear, no comment needed
val enabledVideoTracks = tracks
    .filterIsInstance<VideoTrack>()
    .filter { it.isEnabled }
```

### Comment WHY, Not WHAT

```kotlin
// BAD: Describes what code does
// Check if duration is greater than max
if (duration > MAX_DURATION) {
    // Truncate to max duration
    duration = MAX_DURATION
}

// GOOD: Explains WHY
// Platform limitation: iOS AVFoundation crashes with videos > 4 hours
if (duration > MAX_DURATION) {
    duration = MAX_DURATION
}
```

### Document Public APIs

```kotlin
// BAD: No documentation on public API
fun export(project: Project, options: ExportOptions): Flow<ExportProgress>

// GOOD: Clear documentation
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
```

### No Commented-Out Code

```kotlin
// BAD: Dead code left in comments
fun processVideo(video: Video) {
    // val oldResult = legacyProcess(video)
    // if (oldResult.isValid) {
    //     return oldResult
    // }
    return newProcess(video)
}

// GOOD: Delete unused code (use git history if needed)
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
    assertEquals(1920, result.width)
    val anotherResult = loader.load("test2.mp4")
    assertTrue(anotherResult.isValid)
    whenever(mockFileSystem.exists(any())).thenReturn(false)
    val failResult = loader.load("missing.mp4")
    assertTrue(failResult.isFailure)
}

// GOOD: Clear AAA structure, one assertion focus
@Test
fun `load returns video with correct dimensions`() {
    // Arrange
    val mockFile = createMockVideoFile(width = 1920, height = 1080)
    val loader = VideoLoader(mockFileSystem)

    // Act
    val result = loader.load(mockFile.path)

    // Assert
    assertEquals(1920, result.getOrThrow().width)
    assertEquals(1080, result.getOrThrow().height)
}

@Test
fun `load returns failure when file does not exist`() {
    // Arrange
    whenever(mockFileSystem.exists(any())).thenReturn(false)
    val loader = VideoLoader(mockFileSystem)

    // Act
    val result = loader.load("missing.mp4")

    // Assert
    assertTrue(result.isFailure)
    assertIs<VideoError.NotFound>(result.exceptionOrNull())
}
```

### Test Independence

```kotlin
// BAD: Tests depend on each other or shared mutable state
class VideoTests {
    companion object {
        var sharedVideo: Video? = null  // Shared between tests
    }

    @Test
    fun `test load`() {
        sharedVideo = loadVideo("test.mp4")
        assertNotNull(sharedVideo)
    }

    @Test
    fun `test process`() {
        val result = process(sharedVideo!!)  // Depends on previous test
        assertTrue(result.isSuccess)
    }
}

// GOOD: Each test is independent
class VideoTests {
    private lateinit var loader: VideoLoader

    @BeforeEach
    fun setup() {
        loader = VideoLoader(FakeFileSystem())
    }

    @Test
    fun `load returns valid video`() {
        val video = loader.load("test.mp4")
        assertNotNull(video)
    }

    @Test
    fun `process transforms video correctly`() {
        val video = createTestVideo()  // Create fresh test data
        val result = process(video)
        assertTrue(result.isSuccess)
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
- [ ] Under 30 lines
- [ ] Max 3 parameters (use data class for more)
- [ ] Max 3 nesting levels

### Classes
- [ ] Single responsibility
- [ ] Dependencies injected via constructor
- [ ] State is immutable where possible
- [ ] Under 200 lines

### Safety
- [ ] No `!!` operators
- [ ] No mutable public properties
- [ ] Errors handled with Result type
- [ ] No generic exception catching

### Async
- [ ] Uses structured concurrency
- [ ] No GlobalScope
- [ ] Dispatchers are injectable

### Tests
- [ ] Descriptive names
- [ ] Independent (no shared mutable state)
- [ ] Clear AAA structure
