# Kotlin Multiplatform

Standards, conventions, and project initialization guide for Compose
Multiplatform projects targeting Desktop, Android, and iOS.

---

## Table of Contents

1. [Project Initialization](#project-initialization)
2. [Test Locations](#test-locations)
3. [Test Runners](#test-runners)

---

## Project Initialization

### CodingStandards Submodule

Every new project adds this repo as a git submodule:

```bash
git submodule add git@github.com:x128/CodingStandards.git CodingStandards
```

The project's `CLAUDE.md` then references the standards:

```markdown
## Standards
Follow `CodingStandards/CLEAN_CODE.md`
Follow `CodingStandards/KOTLIN.md`
Follow `CodingStandards/ARCHITECTURE.md`
Follow `CodingStandards/TESTING.md`
Follow `CodingStandards/KOTLIN_MULTIPLATFORM.md`
```

### Proven Version Set

These versions are tested and known to work together (updated 2026-02-21):

| Component | Version |
|-----------|---------|
| Kotlin | 2.0.21 |
| Compose Multiplatform | 1.7.1 |
| Gradle | 8.13 |
| AGP | 8.5.2 |
| JDK (build) | 17 |

> **JDK 25 workaround**: macOS Homebrew installs JDK 25 as default, but
> Gradle doesn't support it. Pin JDK 17 in `gradle.properties` (see below).
> Install with `brew install openjdk@17` if missing.

### gradle.properties

```properties
# Gradle
org.gradle.jvmargs=-Xmx2048M -Dfile.encoding=UTF-8 -Dkotlin.daemon.jvm.options\="-Xmx2048M"
org.gradle.java.home=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home
org.gradle.parallel=true
org.gradle.caching=true

# Kotlin
kotlin.code.style=official
```

### gradle/libs.versions.toml

Start with the minimum — add libraries as tasks require them:

```toml
[versions]
kotlin = "2.0.21"
compose-multiplatform = "1.7.1"
agp = "8.5.2"

[plugins]
kotlinMultiplatform = { id = "org.jetbrains.kotlin.multiplatform", version.ref = "kotlin" }
composeCompiler = { id = "org.jetbrains.kotlin.plugin.compose", version.ref = "kotlin" }
composeMultiplatform = { id = "org.jetbrains.compose", version.ref = "compose-multiplatform" }
androidApplication = { id = "com.android.application", version.ref = "agp" }
```

### Project Structure

Desktop-first. Android/iOS source sets exist but are not wired until needed.

```
project/
├── CodingStandards/              # submodule
├── composeApp/
│   ├── build.gradle.kts
│   └── src/
│       ├── commonMain/kotlin/    # shared UI and logic
│       ├── desktopMain/kotlin/   # desktop entry point
│       ├── androidMain/kotlin/   # empty until wired
│       └── iosMain/kotlin/       # empty until wired
├── build.gradle.kts              # root — plugins apply false
├── settings.gradle.kts
├── gradle.properties
├── gradle/
│   ├── libs.versions.toml
│   └── wrapper/
├── gradlew
└── gradlew.bat
```

### .gitignore

```gitignore
*.iml
.gradle
.idea
.claude/settings.local.json
.DS_Store
build/
local.properties
```

### composeApp/build.gradle.kts

Desktop target only; Android/iOS commented out for future wiring:

```kotlin
import org.jetbrains.compose.desktop.application.dsl.TargetFormat

plugins {
    alias(libs.plugins.kotlinMultiplatform)
    alias(libs.plugins.composeMultiplatform)
    alias(libs.plugins.composeCompiler)
}

kotlin {
    jvm("desktop")

    // Android and iOS targets configured but not wired yet
    // androidTarget()
    // iosX64()
    // iosArm64()
    // iosSimulatorArm64()

    sourceSets {
        val desktopMain by getting

        commonMain.dependencies {
            implementation(compose.runtime)
            implementation(compose.foundation)
            implementation(compose.material3)
            implementation(compose.ui)
            implementation(compose.components.resources)
        }

        desktopMain.dependencies {
            implementation(compose.desktop.currentOs)
        }
    }
}

compose.desktop {
    application {
        mainClass = "com.example.app.MainKt"

        nativeDistributions {
            targetFormats(TargetFormat.Dmg, TargetFormat.Deb)
            packageName = "AppName"
            packageVersion = "1.0.0"
        }
    }
}
```

### Gradle Wrapper

Copy `gradlew`, `gradlew.bat`, and `gradle/wrapper/gradle-wrapper.jar` from
an existing project or download from the
[Gradle releases](https://gradle.org/releases/) page.

### Verification

After setup, the following must pass:

```bash
./gradlew :composeApp:run
```

This should launch a desktop window with placeholder UI.

---

## Test Locations

| Type | Location | Framework |
|---|---|---|
| Unit, Integration | `shared/src/commonTest/kotlin/...` | kotlin.test, Turbine |
| Desktop end-to-end | `shared/src/desktopTest/` | `compose.desktop.uiTestJUnit4` |
| Android end-to-end | `androidApp/src/androidTest/` | `androidx.compose.ui:ui-test-junit4` |
| iOS end-to-end | `iosApp/{App}UITests/` | XCUITest (Swift) |

Unit and integration test files mirror main source package structure.
End-to-end tests follow platform conventions.

---

## Test Runners

| Scope | Command |
|---|---|
| Desktop (unit + integration + E2E) | `./gradlew :shared:desktopTest` |
| iOS (unit + integration) | `./gradlew :shared:iosSimulatorArm64Test` |
| iOS (E2E) | `xcodebuild test -project iosApp/{App}.xcodeproj -scheme {App} -destination 'platform=iOS Simulator,name=iPhone 17 Pro'` |
| Android (E2E) | `./gradlew :androidApp:connectedAndroidTest` |
