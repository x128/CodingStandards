# Swift / iOS Coding Standards

## Table of Contents
1. [Naming](#naming)
2. [Functions](#functions)
3. [Types](#types)
4. [Optionals](#optionals)
5. [Error Handling](#error-handling)
6. [State Management](#state-management)
7. [Concurrency](#concurrency)
8. [Collections](#collections)
9. [SwiftUI](#swiftui)
10. [Testing](#testing)

---

## Naming

### Variables

```swift
// BAD
let d = Date()
let vc = UIViewController()
let arr = [String]()
let flag = true
let temp = calculate()

// GOOD
let createdDate = Date()
let profileViewController = UIViewController()
let userNames = [String]()
let isDownloadEnabled = true
let optimizedBitrate = calculateBitrate()
```

### Booleans

```swift
// BAD
var enabled: Bool
var video: Bool
var loading: Bool
var valid: Bool

// GOOD
var isEnabled: Bool
var hasVideo: Bool
var isLoading: Bool
var isValid: Bool
var shouldAutoSave: Bool
var canUndo: Bool
```

### Functions

```swift
// BAD: Unclear, no external parameter names
func process(_ a: String, _ b: Int)
func handle(_ x: Event)
func do()
func data() -> Data

// GOOD: Clear action, readable at call site
func processVideo(at path: String, quality: Int)
func handle(playbackEvent event: PlaybackEvent)
func exportProject()
func loadUserData() -> Data

// Call site reads naturally:
processVideo(at: "/path/to/file", quality: 80)
handle(playbackEvent: .paused)
```

### Types

```swift
// BAD
struct data { }
class videoClass { }
protocol videoProtocol { }
enum state { }

// GOOD
struct VideoMetadata { }
class VideoEncoder { }
protocol VideoEncoding { }  // -ing or -able suffix
enum PlaybackState { }
```

### Constants

```swift
// BAD
let size = 1024 * 1024 * 50
let timeout = 30.0
let ratio = 1.777778

// GOOD
enum Constants {
    static let maxVideoSizeBytes = 50 * 1024 * 1024  // 50 MB
    static let exportTimeoutSeconds: TimeInterval = 30
    static let widescreenAspectRatio: CGFloat = 16.0 / 9.0
}
```

---

## Functions

### Single Responsibility

```swift
// BAD: Does multiple things
func processVideoAndUpload(path: String) {
    let data = FileManager.default.contents(atPath: path)!
    let compressed = compress(data)
    let encoded = encode(compressed)
    let thumbnail = extractThumbnail(encoded)
    saveThumbnail(thumbnail)
    let url = upload(encoded)
    saveToDatabase(url)
    sendNotification()
}

// GOOD: Single responsibility, composable
func compressVideo(_ data: Data) -> Data
func encodeToH264(_ data: Data) -> EncodedVideo
func extractThumbnail(from video: EncodedVideo) -> UIImage
func upload(_ video: EncodedVideo) async throws -> URL

// Compose in a coordinator
func exportAndUpload(path: String) async throws -> ExportResult {
    let data = try loadVideo(at: path)
    let compressed = compressVideo(data)
    let encoded = encodeToH264(compressed)
    let url = try await upload(encoded)
    return ExportResult(url: url)
}
```

### Parameter Labels

```swift
// BAD: Unclear at call site
func move(_ p: CGPoint, _ d: TimeInterval, _ c: UIColor)
// move(point, 2.0, .red) - what do these mean?

// BAD: Redundant
func moveView(view: UIView, toPoint point: CGPoint)
// moveView(view: myView, toPoint: origin) - "view" repeated

// GOOD: Reads like English
func move(to point: CGPoint, duration: TimeInterval, highlightColor: UIColor)
// move(to: origin, duration: 2.0, highlightColor: .red)

func move(_ view: UIView, to point: CGPoint)
// move(myView, to: origin)
```

### Avoid Deep Nesting

```swift
// BAD
func processMedia(file: URL?) -> Result<Media, MediaError> {
    if let file = file {
        if FileManager.default.fileExists(atPath: file.path) {
            if FileManager.default.isReadableFile(atPath: file.path) {
                if let data = try? Data(contentsOf: file) {
                    if !data.isEmpty {
                        if isValidFormat(data) {
                            return .success(parse(data))
                        } else {
                            return .failure(.invalidFormat)
                        }
                    } else {
                        return .failure(.emptyFile)
                    }
                } else {
                    return .failure(.readFailed)
                }
            } else {
                return .failure(.notReadable)
            }
        } else {
            return .failure(.notFound)
        }
    } else {
        return .failure(.nilURL)
    }
}

// GOOD: Guard statements, early exit
func processMedia(file: URL?) -> Result<Media, MediaError> {
    guard let file = file else { return .failure(.nilURL) }
    guard FileManager.default.fileExists(atPath: file.path) else { return .failure(.notFound) }
    guard FileManager.default.isReadableFile(atPath: file.path) else { return .failure(.notReadable) }
    guard let data = try? Data(contentsOf: file) else { return .failure(.readFailed) }
    guard !data.isEmpty else { return .failure(.emptyFile) }
    guard isValidFormat(data) else { return .failure(.invalidFormat) }

    return .success(parse(data))
}
```

---

## Types

### Prefer Structs

```swift
// BAD: Class for simple data
class VideoSettings {
    var resolution: CGSize
    var frameRate: Int
    var codec: String

    init(resolution: CGSize, frameRate: Int, codec: String) {
        self.resolution = resolution
        self.frameRate = frameRate
        self.codec = codec
    }
}

// GOOD: Struct for value types
struct VideoSettings {
    let resolution: CGSize
    let frameRate: Int
    let codec: Codec
}

// Use class when you need:
// - Identity (===)
// - Inheritance
// - Deinitializers
// - Reference semantics intentionally
```

### Use Enums for Finite States

```swift
// BAD: Stringly typed
func setPlaybackState(_ state: String) {
    if state == "playing" { ... }
    else if state == "paused" { ... }
}

// BAD: Multiple booleans
struct PlayerState {
    var isPlaying: Bool
    var isPaused: Bool
    var isBuffering: Bool
    var isStopped: Bool
    // Can have invalid combinations!
}

// GOOD: Enum with associated values
enum PlaybackState {
    case idle
    case playing(startTime: Date)
    case paused(at: TimeInterval)
    case buffering(progress: Double)
    case failed(Error)
}

// Exhaustive switch
func handle(_ state: PlaybackState) {
    switch state {
    case .idle:
        showPlayButton()
    case .playing(let startTime):
        updatePlaybackUI(since: startTime)
    case .paused(let position):
        showResumeOption(at: position)
    case .buffering(let progress):
        showBufferingIndicator(progress: progress)
    case .failed(let error):
        showError(error)
    }
}
```

### Protocol-Oriented Design

```swift
// BAD: Fat protocol
protocol MediaHandler {
    func loadVideo(from url: URL) -> Video
    func loadAudio(from url: URL) -> Audio
    func saveVideo(_ video: Video, to url: URL)
    func saveAudio(_ audio: Audio, to url: URL)
    func encode(_ video: Video) -> Data
    func decode(_ data: Data) -> Video
    func stream(from url: URL) -> AsyncStream<Frame>
}

// GOOD: Small, focused protocols
protocol VideoLoading {
    func loadVideo(from url: URL) async throws -> Video
}

protocol VideoSaving {
    func save(_ video: Video, to url: URL) async throws
}

protocol VideoEncoding {
    func encode(_ video: Video) throws -> Data
}

// Compose via protocol composition
typealias VideoProcessing = VideoLoading & VideoSaving & VideoEncoding
```

---

## Optionals

### Never Force Unwrap

```swift
// BAD: Crashes at runtime
let duration = video!.duration
let name = dictionary["name"] as! String
let cell = tableView.dequeueReusableCell(withIdentifier: "Cell")!

// GOOD: Safe unwrapping
guard let video = video else { return }
let duration = video.duration

if let name = dictionary["name"] as? String {
    display(name)
}

guard let cell = tableView.dequeueReusableCell(withIdentifier: "Cell") else {
    fatalError("Cell not registered") // Programmer error, crash is appropriate
}
```

### Avoid Implicit Unwrap

```swift
// BAD: IUO as lazy initialization
class ViewController: UIViewController {
    var viewModel: ViewModel!  // Dangerous

    override func viewDidLoad() {
        viewModel = ViewModel()
    }
}

// GOOD: Proper initialization
class ViewController: UIViewController {
    private let viewModel: ViewModel

    init(viewModel: ViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }
}

// ACCEPTABLE: IBOutlets (system guarantees connection)
@IBOutlet private var titleLabel: UILabel!
```

### Nil Coalescing

```swift
// BAD: Verbose optional handling
let displayName: String
if let name = user?.name {
    displayName = name
} else {
    displayName = "Anonymous"
}

// GOOD: Nil coalescing
let displayName = user?.name ?? "Anonymous"

// GOOD: Optional chaining
let trackCount = project?.timeline?.audioTracks?.count ?? 0
```

### Map and FlatMap

```swift
// BAD: Manual unwrap and transform
var formattedDate: String?
if let date = event?.date {
    formattedDate = dateFormatter.string(from: date)
}

// GOOD: map for transform
let formattedDate = event?.date.map { dateFormatter.string(from: $0) }

// GOOD: flatMap when transform returns optional
let firstTrack = project?.tracks.first  // Optional<Track>
let duration = firstTrack.flatMap { $0.duration }  // Optional<TimeInterval>
```

---

## Error Handling

### Use Swift Errors

```swift
// BAD: Return nil on failure
func loadVideo(id: String) -> Video? {
    // Caller has no idea why it failed
}

// BAD: Tuple with error
func loadVideo(id: String) -> (Video?, Error?) {
    // Awkward to use, can have invalid states
}

// GOOD: Throwing function
func loadVideo(id: String) throws -> Video {
    guard let data = storage.read(id) else {
        throw VideoError.notFound(id)
    }
    guard isValidFormat(data) else {
        throw VideoError.invalidFormat
    }
    return try decode(data)
}
```

### Typed Errors

```swift
// BAD: Generic error
enum AppError: Error {
    case error
    case failed
    case unknown
}

// GOOD: Specific, contextual errors
enum VideoError: LocalizedError {
    case notFound(id: String)
    case invalidFormat(expected: String, actual: String)
    case fileTooLarge(size: Int64, maxSize: Int64)
    case encodingFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .notFound(let id):
            return "Video '\(id)' not found"
        case .invalidFormat(let expected, let actual):
            return "Expected \(expected) format but got \(actual)"
        case .fileTooLarge(let size, let maxSize):
            return "File size \(size) exceeds maximum \(maxSize)"
        case .encodingFailed(let underlying):
            return "Encoding failed: \(underlying.localizedDescription)"
        }
    }
}
```

### Result Type

```swift
// GOOD: Result for async callbacks (pre-async/await)
func loadVideo(id: String, completion: @escaping (Result<Video, VideoError>) -> Void)

// Usage
loadVideo(id: "123") { result in
    switch result {
    case .success(let video):
        display(video)
    case .failure(let error):
        showError(error)
    }
}

// Or with get()
loadVideo(id: "123") { result in
    do {
        let video = try result.get()
        display(video)
    } catch {
        showError(error)
    }
}
```

---

## State Management

### Immutable View State

```swift
// BAD: Scattered mutable state
class EditorViewController: UIViewController {
    var currentVideo: Video?
    var isPlaying = false
    var currentTime: TimeInterval = 0
    var error: String?

    func play() {
        isPlaying = true
        // Who updates the UI?
    }
}

// GOOD: Single immutable state
struct EditorState: Equatable {
    var video: Video?
    var playbackState: PlaybackState = .idle
    var currentTime: TimeInterval = 0
    var error: String?
}

enum PlaybackState: Equatable {
    case idle
    case playing
    case paused
    case buffering(Double)
}

// In ViewModel/Store
@Published private(set) var state = EditorState()

func play() {
    state = state.copy(playbackState: .playing)
}
```

### Unidirectional Flow

```swift
// BAD: Two-way binding, state mutation everywhere
class EditorView: UIView {
    func onPlayTapped() {
        viewModel.isPlaying = true
        playButton.setImage(pauseIcon, for: .normal)
        progressBar.startAnimating()
    }
}

// GOOD: Actions up, state down
enum EditorAction {
    case playTapped
    case pauseTapped
    case seek(to: TimeInterval)
    case videoLoaded(Video)
}

class EditorViewModel: ObservableObject {
    @Published private(set) var state = EditorState()

    func send(_ action: EditorAction) {
        switch action {
        case .playTapped:
            state.playbackState = .playing
            player.play()
        case .pauseTapped:
            state.playbackState = .paused
            player.pause()
        case .seek(let time):
            state.currentTime = time
            player.seek(to: time)
        case .videoLoaded(let video):
            state.video = video
        }
    }
}

// View just renders state
struct EditorView: View {
    @ObservedObject var viewModel: EditorViewModel

    var body: some View {
        PlaybackControls(
            isPlaying: viewModel.state.playbackState == .playing,
            onPlay: { viewModel.send(.playTapped) },
            onPause: { viewModel.send(.pauseTapped) }
        )
    }
}
```

---

## Concurrency

### Prefer async/await

```swift
// BAD: Callback hell
func loadProject(id: String, completion: @escaping (Project?) -> Void) {
    loadMetadata(id: id) { metadata in
        guard let metadata = metadata else {
            completion(nil)
            return
        }
        loadTracks(for: metadata) { tracks in
            guard let tracks = tracks else {
                completion(nil)
                return
            }
            loadAssets(for: tracks) { assets in
                guard let assets = assets else {
                    completion(nil)
                    return
                }
                let project = Project(metadata: metadata, tracks: tracks, assets: assets)
                completion(project)
            }
        }
    }
}

// GOOD: async/await
func loadProject(id: String) async throws -> Project {
    let metadata = try await loadMetadata(id: id)
    let tracks = try await loadTracks(for: metadata)
    let assets = try await loadAssets(for: tracks)
    return Project(metadata: metadata, tracks: tracks, assets: assets)
}
```

### Structured Concurrency

```swift
// BAD: Unstructured task
func loadAllMedia() {
    Task.detached {  // No parent, can't be cancelled
        await loadVideos()
        await loadImages()
    }
}

// GOOD: Structured concurrency
func loadAllMedia() async throws -> (videos: [Video], images: [Image]) {
    async let videos = loadVideos()
    async let images = loadImages()
    return try await (videos, images)
}

// GOOD: TaskGroup for dynamic concurrency
func processVideos(_ videos: [Video]) async throws -> [ProcessedVideo] {
    try await withThrowingTaskGroup(of: ProcessedVideo.self) { group in
        for video in videos {
            group.addTask {
                try await process(video)
            }
        }
        return try await group.reduce(into: []) { $0.append($1) }
    }
}
```

### Actor Isolation

```swift
// BAD: Shared mutable state with locks
class VideoCache {
    private var cache = [String: Video]()
    private let lock = NSLock()

    func get(_ id: String) -> Video? {
        lock.lock()
        defer { lock.unlock() }
        return cache[id]
    }

    func set(_ video: Video, for id: String) {
        lock.lock()
        defer { lock.unlock() }
        cache[id] = video
    }
}

// GOOD: Actor for thread safety
actor VideoCache {
    private var cache = [String: Video]()

    func get(_ id: String) -> Video? {
        cache[id]
    }

    func set(_ video: Video, for id: String) {
        cache[id] = video
    }

    func getOrLoad(_ id: String, loader: () async throws -> Video) async throws -> Video {
        if let cached = cache[id] {
            return cached
        }
        let video = try await loader()
        cache[id] = video
        return video
    }
}
```

### MainActor for UI

```swift
// BAD: Manual dispatch to main
func loadVideo() {
    Task {
        let video = try await videoLoader.load(id)
        DispatchQueue.main.async {
            self.state.video = video  // Easy to forget
        }
    }
}

// GOOD: MainActor annotation
@MainActor
class EditorViewModel: ObservableObject {
    @Published private(set) var state = EditorState()

    func loadVideo() async {
        do {
            let video = try await videoLoader.load(id)
            state.video = video  // Guaranteed main thread
        } catch {
            state.error = error.localizedDescription
        }
    }
}
```

---

## Collections

### Prefer Immutable

```swift
// BAD: Exposing mutable collection
class Playlist {
    var tracks = [Track]()  // Anyone can mutate
}

// GOOD: Encapsulated mutation
struct Playlist {
    private(set) var tracks: [Track] = []

    mutating func add(_ track: Track) {
        tracks.append(track)
    }

    mutating func remove(at index: Int) {
        tracks.remove(at: index)
    }
}
```

### Functional Transforms

```swift
// BAD: Imperative mutation
func getActiveVideoTracks(from project: Project) -> [VideoTrack] {
    var result = [VideoTrack]()
    for track in project.tracks {
        if let videoTrack = track as? VideoTrack {
            if videoTrack.isEnabled && !videoTrack.clips.isEmpty {
                result.append(videoTrack)
            }
        }
    }
    return result
}

// GOOD: Functional chain
func getActiveVideoTracks(from project: Project) -> [VideoTrack] {
    project.tracks
        .compactMap { $0 as? VideoTrack }
        .filter { $0.isEnabled && !$0.clips.isEmpty }
}
```

### Lazy for Large Collections

```swift
// BAD: Creates intermediate arrays
let result = hugeArray
    .map { transform($0) }      // New array
    .filter { $0.isValid }      // Another new array
    .prefix(10)                 // Finally takes 10

// GOOD: Lazy evaluation
let result = hugeArray.lazy
    .map { transform($0) }
    .filter { $0.isValid }
    .prefix(10)

// Or use Array() at the end if you need an array
let resultArray = Array(hugeArray.lazy
    .map { transform($0) }
    .filter { $0.isValid }
    .prefix(10))
```

---

## SwiftUI

### View Composition

```swift
// BAD: Massive view body
struct EditorView: View {
    var body: some View {
        VStack {
            // 50 lines of header code
            // 100 lines of timeline code
            // 50 lines of controls code
            // 30 lines of toolbar code
        }
    }
}

// GOOD: Composed small views
struct EditorView: View {
    var body: some View {
        VStack {
            EditorHeader()
            TimelineView()
            PlaybackControls()
            EditorToolbar()
        }
    }
}
```

### Extract Subviews

```swift
// BAD: Complex inline view
struct TrackListView: View {
    var body: some View {
        ForEach(tracks) { track in
            HStack {
                Image(systemName: track.icon)
                    .foregroundColor(track.isEnabled ? .primary : .gray)
                VStack(alignment: .leading) {
                    Text(track.name)
                        .font(.headline)
                    Text(track.duration.formatted())
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button(action: { toggleTrack(track) }) {
                    Image(systemName: track.isEnabled ? "eye" : "eye.slash")
                }
            }
            .padding()
            .background(track.isSelected ? Color.blue.opacity(0.2) : Color.clear)
        }
    }
}

// GOOD: Extracted row view
struct TrackRow: View {
    let track: Track
    let onToggle: () -> Void

    var body: some View {
        HStack {
            TrackIcon(track: track)
            TrackInfo(track: track)
            Spacer()
            ToggleButton(isEnabled: track.isEnabled, action: onToggle)
        }
        .padding()
        .background(track.isSelected ? Color.blue.opacity(0.2) : Color.clear)
    }
}

struct TrackListView: View {
    var body: some View {
        ForEach(tracks) { track in
            TrackRow(track: track) {
                toggleTrack(track)
            }
        }
    }
}
```

### Prefer Value Types in Views

```swift
// BAD: Reference type causes unnecessary updates
class TrackModel: ObservableObject {
    @Published var name: String
    @Published var duration: TimeInterval
}

struct TrackView: View {
    @ObservedObject var model: TrackModel  // Entire view rebuilds on any change
}

// GOOD: Value type, only affected views update
struct Track: Identifiable, Equatable {
    let id: UUID
    var name: String
    var duration: TimeInterval
}

struct TrackView: View {
    let track: Track  // Only rebuilds when track changes
}
```

---

## Testing

### Test Naming

```swift
// BAD
func testVideo()
func test1()
func testExport()

// GOOD: Describes behavior
func test_loadVideo_returnsVideo_whenFileExists()
func test_loadVideo_throwsNotFound_whenFileMissing()
func test_export_failsWithClearError_whenNoTracks()
```

### Arrange-Act-Assert

```swift
// BAD: Mixed concerns
func test_videoProcessing() {
    let processor = VideoProcessor()
    let result = processor.process(testVideo)
    XCTAssertNotNil(result)
    let anotherResult = processor.process(anotherVideo)
    XCTAssertEqual(anotherResult.duration, 120)
    processor.settings.quality = .low
    let lowQualityResult = processor.process(testVideo)
    XCTAssertLessThan(lowQualityResult.size, result!.size)
}

// GOOD: Clear AAA structure
func test_process_returnsVideoWithCorrectDuration() {
    // Arrange
    let processor = VideoProcessor()
    let input = Video.stub(duration: 120)

    // Act
    let result = try processor.process(input)

    // Assert
    XCTAssertEqual(result.duration, 120)
}

func test_process_reducesFileSize_whenQualityIsLow() {
    // Arrange
    let processor = VideoProcessor(quality: .low)
    let input = Video.stub(size: 1000)

    // Act
    let result = try processor.process(input)

    // Assert
    XCTAssertLessThan(result.size, input.size)
}
```

### Protocol-Based Mocking

```swift
// Define protocol
protocol VideoLoading {
    func load(id: String) async throws -> Video
}

// Production implementation
class VideoLoader: VideoLoading {
    func load(id: String) async throws -> Video {
        // Real implementation
    }
}

// Test mock
class MockVideoLoader: VideoLoading {
    var stubbedVideo: Video?
    var stubbedError: Error?
    var loadCallCount = 0
    var lastLoadedId: String?

    func load(id: String) async throws -> Video {
        loadCallCount += 1
        lastLoadedId = id
        if let error = stubbedError { throw error }
        return stubbedVideo ?? Video.stub()
    }
}

// Test
func test_viewModel_loadsVideo_onAppear() async {
    // Arrange
    let mockLoader = MockVideoLoader()
    mockLoader.stubbedVideo = Video.stub(id: "123")
    let viewModel = EditorViewModel(loader: mockLoader)

    // Act
    await viewModel.onAppear()

    // Assert
    XCTAssertEqual(mockLoader.loadCallCount, 1)
    XCTAssertEqual(viewModel.state.video?.id, "123")
}
```

---

## Summary Checklist

### Naming
- [ ] Variables describe content, not type
- [ ] Functions are verbs describing action
- [ ] Booleans have is/has/can/should prefix
- [ ] Types are PascalCase nouns
- [ ] Protocols end in -ing, -able, or describe capability

### Safety
- [ ] No force unwraps (`!`) except IBOutlets
- [ ] Guard statements for early exit
- [ ] Errors are typed and descriptive
- [ ] No implicitly unwrapped optionals (except IBOutlets)

### Types
- [ ] Structs for value types
- [ ] Enums for finite states
- [ ] Protocols are small and focused
- [ ] Classes only when identity/inheritance needed

### Concurrency
- [ ] async/await over callbacks
- [ ] Structured concurrency (no Task.detached for normal work)
- [ ] Actors for shared mutable state
- [ ] @MainActor for UI code

### SwiftUI
- [ ] Views are small and composable
- [ ] State flows unidirectionally
- [ ] Prefer value types
- [ ] Extract reusable components
