# What the project can use

There is no network and no package manager here. This is everything that is on the classpath.

## Language and general libraries

- Kotlin 2.0.21 with its standard library, on Java 17. The Java standard library is available.
- `kotlinx.coroutines` 1.8.0, including `Flow`.
- For tests: `kotlin.test` (`@Test`, `@BeforeTest`, `assertEquals`, ...), `kotlinx-coroutines-test` 1.8.0 (`runTest`, `StandardTestDispatcher`), Turbine 1.0.0 (`app.cash.turbine.test`).
- In a test, a dispatcher has to share the scheduler of `runTest`: `StandardTestDispatcher(testScheduler)`. Without `testScheduler` the coroutines never run.
- A test must end. A test that leaves a coroutine running for ever (for example a ViewModel that was not cleared) is stopped by `./build.sh` after 60 seconds and named in its output.

There is no dependency-injection library, no UI toolkit, no database library other than `lib.store`, and no mocking library.

## `lib.store`: storage

Keeps rows in files. This is the only way to store data that survives a restart of the app.

```kotlin
package lib.store

class Store(directory: java.io.File, broken: Boolean = false) {
    fun table(name: String): Table        // name: lower-case letters, digits and "_"
}

class Table {
    fun all(): List<Row>                  // rows in the order in which they were first put
    fun find(id: String): Row?
    fun put(row: Row)                     // adds the row, or replaces the row with the same id
    fun delete(id: String)                // does nothing if there is no such row
    fun observeAll(): kotlinx.coroutines.flow.Flow<List<Row>>
}

data class Row(val id: String, val fields: Map<String, String>)

class StoreException(message: String, cause: Throwable? = null) : RuntimeException(message, cause)
```

- All functions block the calling thread while they read or write the file.
- `all`, `find`, `put` and `delete` throw `StoreException` when the file cannot be read or written.
- `observeAll` gives the rows now and again after a `put` or `delete` on that table. A slow collector may miss lists in between; it always gets the latest one. It may get a list equal to the one before. The flow does not end by itself. The file is read on the collector's side: if it cannot be read, the flow ends with `StoreException` at the collector.
- `store.table("x")` gives the same table object every time for one `Store`. Use one `Store` object for one directory: a second one does not tell the observers of the first.
- `Store` creates the directory when it first writes.
- `Store(directory, broken = true)` is for tests: every call throws `StoreException`, and `observeAll` ends with it.
- The app makes its own ids, for example with `java.util.UUID`.
- There are no transactions. Each `put` or `delete` is complete or not done at all, but two calls are two separate changes.
- Field values are text. Any text is allowed in ids, field names and values.

## `lib.rates`: the rates service

```kotlin
package lib.rates

class RatesClient(baseUrl: String) {
    fun eurRatesOn(date: String): Map<String, String>

    companion object { const val DEMO_URL = "demo://rates" }
}

class RatesException(message: String, cause: Throwable? = null) : RuntimeException(message, cause)
```

- `eurRatesOn("2026-03-06")` asks the service how many units of each currency one EUR buys on that day, for example `{"USD": "1.10", "GBP": "0.85", ...}`. EUR is not in the map. Values are decimal numbers as text.
- The map is empty when the service has no rates for that day.
- The call blocks while it waits for the network. It throws `RatesException` when the service cannot be reached.
- `date` must be `YYYY-MM-DD`; anything else is an `IllegalArgumentException`.
- With `RatesClient.DEMO_URL` the client answers from built-in demo data and needs no network: the same rates for USD, GBP, CHF, PLN, CZK, SEK and NOK on every working day, and no rates on Saturdays and Sundays. With any other URL it cannot reach the service here.

## `lib.notify`: notifications

```kotlin
package lib.notify

class Notifications(unreachable: Set<String> = emptySet()) {
    fun post(recipient: String, text: String)
    val delivered: List<Notification>
}

data class Notification(val recipient: String, val text: String)

class NotificationException(message: String) : RuntimeException(message)
```

- `post` sends a notification to a person's phone. It blocks. It throws `NotificationException` when the notification cannot be delivered.
- `delivered` lists what has been delivered through this object.
- `unreachable` names recipients to whom nothing can be delivered. It is there for demos and tests.

## `lib.ui`: the base class of a ViewModel

```kotlin
package lib.ui

abstract class ViewModel(dispatcher: kotlinx.coroutines.CoroutineDispatcher) {
    protected val viewModelScope: kotlinx.coroutines.CoroutineScope
    fun clear()                           // cancels viewModelScope; the system calls it when the screen is gone
}
```

- `viewModelScope` runs coroutines on the given dispatcher. A failure of one coroutine does not cancel the others. The dispatcher that the system gives may be blocked by calls of `lib.store`, `lib.rates` and `lib.notify`.
- An exception that leaves a coroutine started in `viewModelScope` is not handled by anyone: on a device it ends the app.

## What the system needs from the app

There is no `main` function and no drawing code. The system that hosts the app needs one place in the app from which it can get:

- the ViewModel of each screen in `REQUIREMENTS.md`, section 9;
- the daily job of `REQUIREMENTS.md`, section 6, as something it can run.

The system gives that place: the directory for `Store`, a `RatesClient`, a `Notifications` object, a `CoroutineDispatcher`, and a way to ask for today's date. How this place looks is up to the project.
