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

// GOOD: Call site reads naturally
processVideo(at: "/path/to/file", quality: 80)
handle(playbackEvent: .paused)
```

### Types

A protocol name takes an -ing or -able suffix, as `VideoEncoding` does.

```swift
// BAD
struct data { }
class videoClass { }
protocol videoProtocol { }
enum state { }

// GOOD
struct VideoMetadata { }
class VideoEncoder { }
protocol VideoEncoding { }
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
    static let megabyte = 1024 * 1024
    static let maxVideoSizeBytes = 50 * megabyte
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

// GOOD: Compose in a coordinator
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
// BAD: Unclear at call site: move(point, 2.0, .red)
func move(_ p: CGPoint, _ d: TimeInterval, _ c: UIColor)

// BAD: Redundant, "view" repeated: moveView(view: myView, toPoint: origin)
func moveView(view: UIView, toPoint point: CGPoint)

// GOOD: Reads like English: move(to: origin, duration: 2.0, highlightColor: .red)
func move(to point: CGPoint, duration: TimeInterval, highlightColor: UIColor)

// GOOD: Reads like English: move(myView, to: origin)
func move(_ view: UIView, to point: CGPoint)
```

### Avoid Deep Nesting

```swift
// BAD
func processMedia(file: URL?) throws -> ProcessMediaResult {
    if let file = file {
        if FileManager.default.fileExists(atPath: file.path) {
            if FileManager.default.isReadableFile(atPath: file.path) {
                let data = try read(file)
                if !data.isEmpty {
                    if isValidFormat(data) {
                        return .media(parse(data))
                    } else {
                        return .invalidFormat
                    }
                } else {
                    return .emptyFile
                }
            } else {
                return .notReadable
            }
        } else {
            return .notFound
        }
    } else {
        return .nilURL
    }
}

// GOOD: Guard statements, early exit
func processMedia(file: URL?) throws -> ProcessMediaResult {
    guard let file = file else { return .nilURL }
    guard FileManager.default.fileExists(atPath: file.path) else { return .notFound }
    guard FileManager.default.isReadableFile(atPath: file.path) else { return .notReadable }
    let data = try read(file)
    guard !data.isEmpty else { return .emptyFile }
    guard isValidFormat(data) else { return .invalidFormat }

    return .media(parse(data))
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
```

Use a class when you need identity (`===`), inheritance, a deinitializer, or reference semantics on purpose.

### Use Enums for Finite States

```swift
// BAD: Stringly typed
func setPlaybackState(_ state: String) {
    if state == "playing" { ... }
    else if state == "paused" { ... }
}

// BAD: Multiple booleans can have invalid combinations
struct PlayerState {
    var isPlaying: Bool
    var isPaused: Bool
    var isBuffering: Bool
    var isStopped: Bool
}

// GOOD: Enum with associated values; a failed playback shows the general message (Error Handling)
enum PlaybackState {
    case idle
    case playing(startTime: Date)
    case paused(at: TimeInterval)
    case buffering(progress: Double)
    case failed
}

// GOOD: Exhaustive switch
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
    case .failed:
        showGeneralError()
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

// GOOD: Compose via protocol composition
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

// GOOD: A bug stops the program
guard let cell = tableView.dequeueReusableCell(withIdentifier: "Cell") else {
    fatalError("Cell not registered")
}
```

### Avoid Implicit Unwrap

```swift
// BAD: IUO as lazy initialization is dangerous
class ViewController: UIViewController {
    var viewModel: ViewModel!

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
let firstTrack: Track? = project?.tracks.first
let duration: TimeInterval? = firstTrack.flatMap { $0.duration }
```

---

## Error Handling

A function reports a failure according to its kind (CLEAN_CODE.md, Error Handling):

- A bug (a broken precondition or invariant) stops the program: `precondition`, `fatalError`.
- An outcome that the requirements name, such as "video not found", is a case of the enum that the function returns. The signature names it and the caller must handle it. When the only such outcome is "there is none", the function returns `nil`.
- Any other failure of storage, network or the platform is thrown as the application's own `Error` type, with a message and the library's error as the cause, by the code that calls the library. That code catches only the library's own error types, never every error. Only the code that started the operation catches the application's error.

`CancellationError` is not a failure. It is passed on as it is: never wrapped, never shown to the user as an error.

### Use Swift Errors

```swift
// BAD: nil for every failure. The caller cannot tell "no such video" from a disk that cannot be read
func loadVideo(id: String) -> Video? {
    try? decode(Data(contentsOf: videoURL(id: id)))
}

// BAD: Tuple with error is awkward to use and can have invalid states
func loadVideo(id: String) -> (Video?, Error?) {
    do {
        return (try decode(Data(contentsOf: videoURL(id: id))), nil)
    } catch {
        return (nil, error)
    }
}

// GOOD: nil says "there is none". Any other failure is thrown as the application's
// own error, with a message and the library's error as the cause. A bug stops the program
struct StorageError: LocalizedError {
    let message: String
    let cause: any Error

    var errorDescription: String? { message }
}

// GOOD: Code that calls a library catches only the library's own error types, through this one function
func storageCall<T>(_ message: String, _ call: () throws -> T) throws -> T {
    do {
        return try call()
    } catch let error as CocoaError {
        throw StorageError(message: message, cause: error)
    } catch let error as DecodingError {
        throw StorageError(message: message, cause: error)
    }
}

// GOOD: The same function for a library call that is async
func storageCall<T>(_ message: String, _ call: () async throws -> T) async throws -> T {
    do {
        return try await call()
    } catch let error as URLError {
        throw StorageError(message: message, cause: error)
    }
}

// GOOD: A missing file is the outcome "there is none", not a failure: loadVideo turns it into nil before storageCall sees it
func loadVideo(id: String) throws -> Video? {
    precondition(!id.isEmpty, "Video id is empty")
    let data: Data? = try storageCall("Cannot read video \(id)") {
        do {
            return try Data(contentsOf: videoURL(id: id))
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        }
    }
    guard let data else { return nil }
    return try storageCall("Cannot decode video \(id)") { try decode(data) }
}

// GOOD: Code that starts an operation catches only StorageError, through this one function.
// CancellationError passes: it ends the task and is never shown. Any other error is a bug: it stops the program
@discardableResult
func launchCatchingStorage(
    onStorageFailure: @escaping @MainActor () -> Void,
    _ operation: @escaping @MainActor () async throws -> Void
) -> Task<Void, Never> {
    Task { @MainActor in
        do {
            try await operation()
        } catch is StorageError {
            onStorageFailure()
        } catch is CancellationError {
        } catch {
            fatalError("Unexpected error: \(error)")
        }
    }
}
```

In a Kotlin Multiplatform app, Swift calls Kotlin use cases. A Kotlin `StorageException` and a Kotlin cancellation reach Swift as an `NSError` with the domain `KotlinException`; the Kotlin object is in `userInfo["KotlinException"]`, as `StorageException` and `KotlinCancellationException`. The same one function recognizes them too:

```swift
// GOOD: Kotlin's StorageException is shown like StorageError, Kotlin's cancellation passes like CancellationError
@discardableResult
func launchCatchingStorage(
    onStorageFailure: @escaping @MainActor () -> Void,
    _ operation: @escaping @MainActor () async throws -> Void
) -> Task<Void, Never> {
    Task { @MainActor in
        do {
            try await operation()
        } catch is StorageError {
            onStorageFailure()
        } catch let error as NSError where error.userInfo["KotlinException"] is StorageException {
            onStorageFailure()
        } catch is CancellationError {
        } catch let error as NSError where error.userInfo["KotlinException"] is KotlinCancellationException {
        } catch {
            fatalError("Unexpected error: \(error)")
        }
    }
}
```

### Named Outcomes, Not Generic Errors

```swift
// BAD: Generic error
enum AppError: Error {
    case error
    case failed
    case unknown
}

// GOOD: The function's own result type has one case for each outcome that the requirements name.
// Each case is specific and carries the values that explain it
enum OpenVideoResult {
    case opened(Video)
    case notFound(id: String)
    case tooLong(duration: TimeInterval, limit: TimeInterval)
}

func openVideo(id: String) throws -> OpenVideoResult {
    guard let video = try loadVideo(id: id) else {
        return .notFound(id: id)
    }
    guard video.duration <= maxDuration else {
        return .tooLong(duration: video.duration, limit: maxDuration)
    }
    return .opened(video)
}
```

### Result Type

```swift
// GOOD: Result for async callbacks (pre-async/await). What the function would throw is .failure
func openVideo(id: String, completion: @escaping @Sendable (Result<OpenVideoResult, Error>) -> Void) {
    DispatchQueue.global().async {
        completion(Result { try openVideo(id: id) })
    }
}

// Usage: .failure is thrown again, so launchCatchingStorage catches only StorageError and shows a general message
openVideo(id: "123") { result in
    launchCatchingStorage(onStorageFailure: showGeneralError) {
        switch result {
        case .success(.opened(let video)):
            display(video)
        case .success(.notFound(let id)):
            showNotFound(id: id)
        case .success(.tooLong(_, let limit)):
            showTooLong(limit: limit)
        case .failure(let error):
            throw error
        }
    }
}

// GOOD: get() turns the Result back into a throwing call
openVideo(id: "123") { result in
    launchCatchingStorage(onStorageFailure: showGeneralError) {
        show(try result.get())
    }
}
```

---

## State Management

### Immutable View State

```swift
// BAD: Scattered mutable state, nothing says who updates the UI
class EditorViewController: UIViewController {
    var currentVideo: Video?
    var isPlaying = false
    var currentTime: TimeInterval = 0
    var error: String?

    func play() {
        isPlaying = true
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

// GOOD: The ViewModel or store holds the state
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

// GOOD: View just renders state
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
// BAD: Unstructured task has no parent and can't be cancelled
func loadAllMedia() {
    Task.detached {
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
// BAD: Manual dispatch to main is easy to forget
func loadVideo() {
    Task {
        let video = try await videoLoader.load(id)
        DispatchQueue.main.async {
            self.state.video = video
        }
    }
}

// GOOD: MainActor annotation guarantees the main thread. launchCatchingStorage (Error Handling) catches only
// StorageError and shows a general message; CancellationError passes
@MainActor
class EditorViewModel: ObservableObject {
    @Published private(set) var state = EditorState()
    private var loadTask: Task<Void, Never>?

    func loadVideo() {
        loadTask?.cancel()
        loadTask = launchCatchingStorage(onStorageFailure: { self.state.error = "Could not load the video" }) {
            let video = try await self.videoLoader.load(self.id)
            self.state.video = video
        }
    }
}
```

---

## Collections

### Prefer Immutable

```swift
// BAD: Exposing mutable collection, anyone can mutate
class Playlist {
    var tracks = [Track]()
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
// BAD: Creates two intermediate arrays before it takes 10
let result = hugeArray
    .map { transform($0) }
    .filter { $0.isValid }
    .prefix(10)

// GOOD: Lazy evaluation
let result = hugeArray.lazy
    .map { transform($0) }
    .filter { $0.isValid }
    .prefix(10)

// GOOD: Array() at the end if you need an array
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
// BAD: Reference type, the entire view rebuilds on any change
class TrackModel: ObservableObject {
    @Published var name: String
    @Published var duration: TimeInterval
}

struct TrackView: View {
    @ObservedObject var model: TrackModel
}

// GOOD: Value type, only affected views update. TrackView rebuilds only when track changes
struct Track: Identifiable, Equatable {
    let id: UUID
    var name: String
    var duration: TimeInterval
}

struct TrackView: View {
    let track: Track
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
func test_loadVideo_returnsNil_whenFileMissing()
func test_export_returnsNoTracks_whenProjectHasNoTracks()
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
// GOOD: The dependency is a protocol, so the test can pass a mock
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
- [ ] A bug stops the program (`precondition`, `fatalError`)
- [ ] An outcome that the requirements name is returned, not thrown; when there is more than one, each is a case of the function's own result enum and carries the values that explain it
- [ ] Any other failure is thrown as the application's own `Error` type, with a message and the library's error as the cause
- [ ] `CancellationError` is passed on, never wrapped or shown as an error
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
