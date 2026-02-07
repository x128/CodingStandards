# Platform Standards

Platform-specific conventions for Kotlin Multiplatform projects targeting Desktop, Android, and iOS.

---

## Test Locations

| Type | Location | Framework |
|---|---|---|
| Unit, Integration | `shared/src/commonTest/kotlin/...` | kotlin.test, Turbine |
| Desktop end-to-end | `shared/src/desktopTest/` | `compose.desktop.uiTestJUnit4` |
| Android end-to-end | `androidApp/src/androidTest/` | `androidx.compose.ui:ui-test-junit4` |
| iOS end-to-end | `iosApp/{App}UITests/` | XCUITest (Swift) |

Unit and integration test files mirror main source package structure. End-to-end tests follow platform conventions.

## Test Runners

| Scope | Command |
|---|---|
| Desktop (unit + integration + E2E) | `./gradlew :shared:desktopTest` |
| iOS (unit + integration) | `./gradlew :shared:iosSimulatorArm64Test` |
| iOS (E2E) | `xcodebuild test -project iosApp/{App}.xcodeproj -scheme {App} -destination 'platform=iOS Simulator,name=iPhone 17 Pro'` |
| Android (E2E) | `./gradlew :androidApp:connectedAndroidTest` |
