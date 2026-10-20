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

Every new project adds this repo as a git submodule (the user does it):

```bash
git submodule add https://github.com/x128/CodingStandards.git CodingStandards
```

The project's `CLAUDE.md` then references the standards:

```markdown
## Standards
Follow `CodingStandards/CLEAN_CODE.md`
Follow `CodingStandards/KOTLIN.md`
Follow `CodingStandards/SWIFT.md`
Follow `CodingStandards/ARCHITECTURE.md`
Follow `CodingStandards/TESTING.md`
Follow `CodingStandards/KOTLIN_MULTIPLATFORM.md`
Follow `CodingStandards/EXECUTION_GUIDE.md`
```

`SWIFT.md` only when the project has iOS.

### Proven Version Set

These versions build and pass the tests together on Android and iOS, checked
2026-10-19 twice: in a project in development, and in a new project made only
from the templates of this file (iOS framework link, iOS and JVM tests, debug
and release APK):

| Component | Version |
|-----------|---------|
| Kotlin | 2.4.21 |
| Compose Multiplatform | 1.12.2 |
| Navigation 3 (`org.jetbrains.androidx.navigation3`) | 1.2.0-rc01 |
| material3 (`org.jetbrains.compose.material3`) | 1.12.0-alpha03 |
| Gradle | 9.8.2 |
| AGP | 9.4.1 |
| `compileSdk` | 37 |
| JDK (build) | 17 |
| iOS deployment target | 15.0 |

Compose Multiplatform names the Navigation 3 and material3 versions it pairs
with in the Components table of its CHANGELOG; take those, even when they are
pre-releases. Its Android side needs `compileSdk` 37, and that needs AGP 9.2 or
newer.

> **Pin the build JDK — but pin two separate things, separately.** Conflating
> them is why this bites.
>
> **What compiles the code**: `kotlin { jvmToolchain(17) }` in the build script.
> Portable, committed, identical on every machine and in CI. Add it as soon as
> the project has a JVM or Android target — on an iOS-only project there is no
> JVM compilation to pin, and declaring one just asks Gradle to resolve a
> toolchain it may not find (Homebrew's keg-only JDKs are invisible to
> auto-detection without the caveat symlink).
>
> **What Gradle itself runs on**: the daemon's JVM — which a toolchain cannot
> change, because Gradle has to start before it reads your build script. Gradle
> supports new JDKs only after a lag, and Homebrew's default `openjdk` tracks
> the newest release (26 as of 2026-08), so the build dies before configuration
> with an opaque error: the bare version string, `* What went wrong: 26.0.2`,
> no mention of Java. Set `JAVA_HOME`, or `org.gradle.java.home` in
> `~/.gradle/gradle.properties`.
>
> **Never commit `org.gradle.java.home`.** Its value is an absolute path —
> `/opt/homebrew/opt/openjdk@17/…` on Apple Silicon, `/usr/local/…` on Intel,
> different again on Linux CI — so committing it trades a broken build on one
> machine for a broken build on every other one. It is a local override, and
> local overrides live in `~/.gradle/gradle.properties`.
>
> `brew install openjdk@17` only if it is genuinely absent — a machine that
> builds any other KMP project already has it. Homebrew keeps JDKs keg-only, so
> unless the caveat's symlink into `/Library/Java/JavaVirtualMachines` was
> created, `/usr/libexec/java_home -V` will not list them; its silence is not
> evidence of absence.

### gradle.properties

```properties
# Gradle
org.gradle.jvmargs=-Xmx2048M -Dfile.encoding=UTF-8 -Dkotlin.daemon.jvm.options\="-Xmx2048M"
org.gradle.parallel=true
org.gradle.caching=true

# Kotlin
kotlin.code.style=official

# Android
android.useAndroidX=true
```

### gradle/libs.versions.toml

Start with the minimum — add libraries as tasks require them:

```toml
[versions]
kotlin = "2.4.21"
compose-multiplatform = "1.12.2"
compose-material3 = "1.12.0-alpha03"
agp = "9.4.1"
activity-compose = "1.13.0"

[libraries]
compose-runtime = { module = "org.jetbrains.compose.runtime:runtime", version.ref = "compose-multiplatform" }
compose-foundation = { module = "org.jetbrains.compose.foundation:foundation", version.ref = "compose-multiplatform" }
compose-material3 = { module = "org.jetbrains.compose.material3:material3", version.ref = "compose-material3" }
compose-ui = { module = "org.jetbrains.compose.ui:ui", version.ref = "compose-multiplatform" }
compose-components-resources = { module = "org.jetbrains.compose.components:components-resources", version.ref = "compose-multiplatform" }
compose-ui-tooling-preview = { module = "org.jetbrains.compose.ui:ui-tooling-preview", version.ref = "compose-multiplatform" }
activity-compose = { module = "androidx.activity:activity-compose", version.ref = "activity-compose" }

[plugins]
kotlinMultiplatform = { id = "org.jetbrains.kotlin.multiplatform", version.ref = "kotlin" }
composeCompiler = { id = "org.jetbrains.kotlin.plugin.compose", version.ref = "kotlin" }
composeMultiplatform = { id = "org.jetbrains.compose", version.ref = "compose-multiplatform" }
androidApplication = { id = "com.android.application", version.ref = "agp" }
androidMultiplatformLibrary = { id = "com.android.kotlin.multiplatform.library", version.ref = "agp" }
```

The `compose.runtime`, `compose.material3` and other `compose.*` shortcuts of the
Compose Gradle plugin are deprecated: name the dependencies as above.

### Project Structure

Target priority is project-specific. Wire the targets your project needs;
delete the rest.

With AGP 9, the Kotlin Multiplatform plugin no longer works in one module with
`com.android.application`. The Android app is therefore its own module,
`androidApp`, and `composeApp` is a library: the shared code, iOS and desktop,
and for Android only the `actual` declarations.

```
project/
├── CodingStandards/              # submodule
├── composeApp/                   # library: shared code, iOS, desktop
│   ├── build.gradle.kts
│   └── src/
│       ├── commonMain/kotlin/    # shared UI and logic
│       ├── commonTest/kotlin/    # unit and integration tests
│       ├── iosMain/kotlin/       # iOS entry point, iOS implementations of commonMain interfaces
│       ├── iosTest/kotlin/       # tests of iOS code
│       ├── androidMain/kotlin/   # `actual` declarations for Android only
│       └── desktopMain/kotlin/   # desktop entry point (when enabled)
├── androidApp/                   # Android application (when needed)
│   ├── build.gradle.kts
│   └── src/
│       ├── main/                 # AndroidManifest.xml, res/, kotlin/: the activity and
│       │                         #   Android implementations of commonMain interfaces
│       ├── test/kotlin/          # tests of Android code on the JVM
│       └── androidTest/kotlin/   # tests on a device
├── iosApp/                       # Xcode project (when needed)
├── build.gradle.kts              # root — plugins apply false
├── settings.gradle.kts           # include(":composeApp"), include(":androidApp")
├── gradle.properties
├── gradle/
│   ├── libs.versions.toml
│   └── wrapper/
├── gradlew
└── gradlew.bat
```

### settings.gradle.kts

```kotlin
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositories {
        google()
        mavenCentral()
    }
}

enableFeaturePreview("TYPESAFE_PROJECT_ACCESSORS")

rootProject.name = "AppName"

include(":composeApp")
include(":androidApp")
```

`TYPESAFE_PROJECT_ACCESSORS` lets `androidApp` depend on `projects.composeApp`.
Without `rootProject.name` Gradle warns that the accessors break caching.

### build.gradle.kts (root)

```kotlin
plugins {
    alias(libs.plugins.kotlinMultiplatform) apply false
    alias(libs.plugins.composeMultiplatform) apply false
    alias(libs.plugins.composeCompiler) apply false
    alias(libs.plugins.androidApplication) apply false
    alias(libs.plugins.androidMultiplatformLibrary) apply false
}
```

### Android SDK location

`local.properties` holds `sdk.dir=/Users/<you>/Library/Android/sdk` (the
default on macOS); the `ANDROID_HOME` environment variable works too. Without
either, every Android task fails with `SDK location not found`. The file is
local and stays out of git, like `org.gradle.java.home`.

### .gitignore

```gitignore
*.iml
.gradle
.kotlin/
.idea
.claude/settings.local.json
.DS_Store
build/
local.properties

# Xcode
*.xcuserdata
*.xcworkspace
DerivedData/
Pods/
xcuserdata/

# Kotlin/Native
*.klib
*.knm
```

### composeApp/build.gradle.kts

Uncomment the targets your project needs and delete the rest:

```kotlin
import org.jetbrains.compose.desktop.application.dsl.TargetFormat // desktop only

plugins {
    alias(libs.plugins.kotlinMultiplatform)
    alias(libs.plugins.composeMultiplatform)
    alias(libs.plugins.composeCompiler)
    // alias(libs.plugins.androidMultiplatformLibrary)
}

kotlin {
    // Uncomment together with any JVM or Android target — this is what
    // compiles the code. It does not set the JDK Gradle itself runs on.
    // jvmToolchain(17)

    // Android library (uncomment when needed); the app is in androidApp
    // android {
    //     namespace = "com.example.app.shared"
    //     compileSdk = 37
    //     minSdk = 24
    //     androidResources { enable = true }
    //     withHostTest {}
    // }

    // iOS targets (uncomment when needed)
    // listOf(
    //     iosArm64(),
    //     iosSimulatorArm64()
    // ).forEach { iosTarget ->
    //     iosTarget.binaries.framework {
    //         baseName = "ComposeApp"
    //         isStatic = true
    //         binaryOption("bundleId", "com.example.app.ComposeApp")
    //     }
    // }

    // Desktop target (uncomment when needed)
    // jvm("desktop")

    sourceSets {
        commonMain.dependencies {
            implementation(libs.compose.runtime)
            implementation(libs.compose.foundation)
            implementation(libs.compose.material3)
            implementation(libs.compose.ui)
            implementation(libs.compose.components.resources)
        }

        commonTest.dependencies {
            implementation(kotlin("test"))
        }

        // val desktopMain by getting
        // desktopMain.dependencies {
        //     implementation(compose.desktop.currentOs)
        // }
    }
}

// Desktop configuration (uncomment when needed)
// compose.desktop {
//     application {
//         mainClass = "com.example.app.MainKt"
//         nativeDistributions {
//             targetFormats(TargetFormat.Dmg, TargetFormat.Deb)
//             packageName = "AppName"
//             packageVersion = "1.0.0"
//         }
//     }
// }
```

Without `bundleId` the link task warns `Cannot infer a bundle ID from packages
of source files`.

### androidApp/build.gradle.kts

When the project has Android:

```kotlin
plugins {
    alias(libs.plugins.androidApplication)
    alias(libs.plugins.composeMultiplatform)
    alias(libs.plugins.composeCompiler)
}

kotlin {
    jvmToolchain(17)
}

android {
    namespace = "com.example.app"
    compileSdk = 37

    defaultConfig {
        applicationId = "com.example.app"
        minSdk = 24
        targetSdk = 35
        versionCode = 1
        versionName = "1.0.0"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

dependencies {
    implementation(projects.composeApp)
    implementation(libs.compose.runtime)
    implementation(libs.compose.ui)
    implementation(libs.activity.compose)
    implementation(libs.compose.ui.tooling.preview)

    testImplementation(kotlin("test-junit"))
}
```

AGP 9 compiles Kotlin itself: `androidApp` applies no
`org.jetbrains.kotlin.android`. The Compose compiler plugin stays.

`ui-tooling-preview` holds the `@Preview` annotation. It is `implementation`,
not `debugImplementation`: a `@Preview` in `src/main` would otherwise break the
release build.

`androidApp/src/main/AndroidManifest.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">

    <application
        android:label="@string/app_name"
        android:theme="@android:style/Theme.Material.Light.NoActionBar">

        <activity
            android:name=".MainActivity"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
    </application>

</manifest>
```

`androidApp/src/main/res/values/strings.xml`:

```xml
<resources>
    <string name="app_name">AppName</string>
</resources>
```

`androidApp/src/main/kotlin/com/example/app/MainActivity.kt`, where `App()` is
the root composable in `composeApp/src/commonMain`:

```kotlin
package com.example.app

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        setContent { App() }
    }
}
```

#### Gotcha: `kotlin("test")` in androidApp has no `@Test`

In a multiplatform module `kotlin("test")` picks the JUnit flavour on its own; in
`androidApp` it does not, and every `kotlin.test.Test` is an unresolved reference.
Use `kotlin("test-junit")` there.

#### Gotcha: `internal` in composeApp is invisible to androidApp

They are two modules now. Code of `composeApp` that the Android implementations
use is `public`.

### Gradle Wrapper

Copy `gradlew`, `gradlew.bat`, and `gradle/wrapper/` from an existing
project. No global `gradle` is installed — bootstrap from an existing wrapper.

To move to another Gradle version, let the wrapper regenerate itself:
`./gradlew wrapper --gradle-version 9.8.2 --distribution-type bin`. Editing only
`distributionUrl` leaves `gradle-wrapper.jar` and the `gradlew` scripts of the
old version.

### iOS Xcode Project

Name the `.xcodeproj` after the app (e.g., `SimpleStories.xcodeproj`), not
`iosApp.xcodeproj`. Use objectVersion 77 (Xcode 16+,
`PBXFileSystemSynchronizedRootGroup`).

Directory structure inside `iosApp/`:

```
iosApp/
├── {App}.xcodeproj/
├── App/                    # Swift sources (sync group)
│   ├── AppDelegate.swift
│   └── SceneDelegate.swift
├── Assets/                 # Asset catalogs (sync group)
│   └── Assets.xcassets/
└── Info.plist
```

#### Kotlin entry point

`composeApp/src/iosMain/kotlin/com/example/app/MainViewController.kt`:

```kotlin
package com.example.app

import androidx.compose.ui.window.ComposeUIViewController
import platform.UIKit.UIViewController

fun MainViewController(): UIViewController = ComposeUIViewController { App() }
```

The file name gives Swift the class name: `MainViewController.kt` becomes
`MainViewControllerKt`, which `SceneDelegate` below calls. Rename the file and
the Swift code stops compiling.

#### Swift entry point

UIKit AppDelegate + SceneDelegate in separate files.

`App/AppDelegate.swift`:

```swift
import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }
}
```

`App/SceneDelegate.swift`:

```swift
import UIKit
import ComposeApp

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }
        window = UIWindow(windowScene: windowScene)
        window?.rootViewController = MainViewControllerKt.MainViewController()
        window?.makeKeyAndVisible()
    }
}
```

#### Info.plist

Place at `iosApp/Info.plist` (NOT inside the sync group — avoids "Multiple
commands produce Info.plist" error):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CADisableMinimumFrameDurationOnPhone</key>
    <true/>
    <key>UILaunchScreen</key>
    <dict/>
    <key>UIApplicationSceneManifest</key>
    <dict>
        <key>UIApplicationSupportsMultipleScenes</key>
        <false/>
        <key>UISceneConfigurations</key>
        <dict>
            <key>UIWindowSceneSessionRoleApplication</key>
            <array>
                <dict>
                    <key>UISceneConfigurationName</key>
                    <string>Default Configuration</string>
                    <key>UISceneDelegateClassName</key>
                    <string>$(PRODUCT_MODULE_NAME).SceneDelegate</string>
                </dict>
            </array>
        </dict>
    </dict>
</dict>
</plist>
```

#### Key build settings (target level)

| Setting | Value |
|---------|-------|
| `PRODUCT_NAME` | `$(TARGET_NAME)` |
| `GENERATE_INFOPLIST_FILE` | `YES` |
| `INFOPLIST_FILE` | `Info.plist` |
| `ENABLE_USER_SCRIPT_SANDBOXING` | `NO` |
| `IPHONEOS_DEPLOYMENT_TARGET` | `15.0` (supported by Compose Multiplatform 1.12) |

Compose Multiplatform 1.12 supports iOS 14 and newer (kotlinlang.org,
"Compatibility and versions"). The Xcode link still warns:
`libicu.icudtl_dat.o ... was built for newer 'iOS-simulator' version (18.5) than
being linked (15.0)`. The object comes inside the framework from a Compose
Multiplatform dependency. Checked on the iOS 27.1 simulator only; a runtime
older than 18.5 is not checked — the iOS 15.2 simulator does not start on
macOS 27.

#### SDK-conditional framework search paths

Use SDK-conditional settings so only the relevant platform path is active.
Avoids "search path not found" warnings:

```
FRAMEWORK_SEARCH_PATHS[sdk=iphonesimulator*] = $(SRCROOT)/../composeApp/build/bin/iosSimulatorArm64/{config}Framework
FRAMEWORK_SEARCH_PATHS[sdk=iphoneos*] = $(SRCROOT)/../composeApp/build/bin/iosArm64/{config}Framework
```

Where `{config}` = `debug` or `release` per build configuration.

#### Build KMP Framework script phase

Runs before Sources. Set `alwaysOutOfDate = 1` (no output dependencies).
Only `iosSimulatorArm64` and `iosArm64` — no `iosX64`:

```sh
cd "$SRCROOT/.."

# Xcode build phases inherit almost no environment, so the JDK has to be found
# here. Try candidates and fail loudly — a single hardcoded path is committed
# breakage on every machine that is not the one it was written on.
#
# Test the version, not just that some java exists: an inherited JAVA_HOME
# pointing at Homebrew's default (newest) JDK is the common case, and it is
# exactly what Gradle cannot start on.
is_jdk17() {
    [ -x "$1/bin/java" ] || return 1
    "$1/bin/java" -version 2>&1 | head -1 | grep -q '"17[."]'
}

if ! is_jdk17 "$JAVA_HOME"; then
    for candidate in \
        "$(/usr/libexec/java_home -v 17 2>/dev/null)" \
        /opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home \
        /usr/local/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home
    do
        if is_jdk17 "$candidate"; then JAVA_HOME="$candidate"; break; fi
    done
fi
is_jdk17 "$JAVA_HOME" || {
    echo "error: no JDK 17 (JAVA_HOME=${JAVA_HOME:-unset})." >&2
    echo "       Set JAVA_HOME to a 17, or: brew install openjdk@17" >&2
    exit 1
}
export JAVA_HOME
export PATH="$JAVA_HOME/bin:$PATH"

if [ "$CONFIGURATION" = "Debug" ]; then
    CONFIG="Debug"
else
    CONFIG="Release"
fi

if [ "$PLATFORM_NAME" = "iphonesimulator" ]; then
    TASK="link${CONFIG}FrameworkIosSimulatorArm64"
else
    TASK="link${CONFIG}FrameworkIosArm64"
fi

./gradlew :composeApp:$TASK :composeApp:syncComposeResourcesForIos
```

#### Gotcha: Compose resources do not reach the .app on their own

`syncComposeResourcesForIos` is what copies `composeResources` into the app
bundle. Linking the framework does not. Drop it and everything still builds
green — the app then dies at runtime on `MissingResourceException` pointing at a
`compose-resources/` path that was never created. Keep it in the phase from the
start, not from the first resource.

#### Gotcha: simulator caches scene configuration

When switching between scene-based and non-scene app lifecycle, **delete the
app from the simulator** before rebuilding. iOS caches the old scene
configuration and the new one won't take effect.

### Verification

After setup, verify compilation on all active targets:

```bash
# iOS: compiles and links the framework that Xcode takes
./gradlew :composeApp:linkDebugFrameworkIosSimulatorArm64

# Android
./gradlew :androidApp:assembleDebug

# Desktop (when enabled)
# ./gradlew :composeApp:compileKotlinDesktop
```

---

## Test Locations

| Type | Location | Framework |
|---|---|---|
| Unit, Integration | `composeApp/src/commonTest/kotlin/...` | kotlin.test; Turbine for flows, added to `libs.versions.toml` with the first test that needs it |
| iOS code | `composeApp/src/iosTest/kotlin/...` | kotlin.test |
| Android code on the JVM | `androidApp/src/test/kotlin/...` | kotlin-test-junit |
| Desktop end-to-end | `composeApp/src/desktopTest/` | `org.jetbrains.compose.ui:ui-test-junit4` |
| Android end-to-end | `androidApp/src/androidTest/` | `androidx.compose.ui:ui-test-junit4` |
| iOS end-to-end | `iosApp/{App}UITests/` | XCUITest (Swift) |

Unit and integration test files mirror main source package structure.
End-to-end tests follow platform conventions.

---

#### Gotcha: Kotlin/Native rejects commas in backtick test names

`fun \`folders first, then by name\`()` compiles for Android and fails the iOS
test target with `Name contains illegal characters: ","`. The JVM run stays green,
so this surfaces only when the iOS test task runs.

---

## Test Runners

| Scope | Command |
|---|---|
| Shared code on the JVM (unit + integration) | `./gradlew :composeApp:testAndroidHostTest` |
| Android code on the JVM | `./gradlew :androidApp:testDebugUnitTest` |
| Desktop (unit + integration + E2E) | `./gradlew :composeApp:desktopTest` |
| iOS (unit + integration) | `./gradlew :composeApp:iosSimulatorArm64Test` |
| iOS (E2E) | `xcodebuild test -project iosApp/{App}.xcodeproj -scheme {App} -destination 'platform=iOS Simulator,name=iPhone 17 Pro'` |
| Android (E2E) | `./gradlew :androidApp:connectedAndroidTest` |
