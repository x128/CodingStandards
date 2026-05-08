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

These versions are tested and known to work together (updated 2026-05-08):

| Component | Version |
|-----------|---------|
| Kotlin | 2.0.21 |
| Compose Multiplatform | 1.7.1 |
| Gradle | 8.13 |
| AGP | 8.5.2 |
| JDK (build) | 17 |

> **Note on newer versions**: Kotlin 2.1.20 / Compose 1.8.2 work for
> desktop-only projects but raise the minimum iOS deployment target. Use
> the versions above for iOS compatibility.

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

# Android
android.useAndroidX=true
```

### gradle/libs.versions.toml

Start with the minimum — add libraries as tasks require them:

```toml
[versions]
kotlin = "2.0.21"
compose-multiplatform = "1.7.1"
agp = "8.5.2"
activity-compose = "1.9.3"

[libraries]
activity-compose = { module = "androidx.activity:activity-compose", version.ref = "activity-compose" }

[plugins]
kotlinMultiplatform = { id = "org.jetbrains.kotlin.multiplatform", version.ref = "kotlin" }
composeCompiler = { id = "org.jetbrains.kotlin.plugin.compose", version.ref = "kotlin" }
composeMultiplatform = { id = "org.jetbrains.compose", version.ref = "compose-multiplatform" }
androidApplication = { id = "com.android.application", version.ref = "agp" }
```

### Project Structure

Target priority is project-specific. Wire the targets your project needs;
comment out the rest.

```
project/
├── CodingStandards/              # submodule
├── composeApp/
│   ├── build.gradle.kts
│   └── src/
│       ├── commonMain/kotlin/    # shared UI and logic
│       ├── iosMain/kotlin/       # iOS entry point
│       ├── androidMain/          # Android manifest + activity
│       │   ├── AndroidManifest.xml
│       │   └── kotlin/
│       └── desktopMain/kotlin/   # desktop entry point (when enabled)
├── iosApp/                       # Xcode project (when needed)
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

Uncomment the targets your project needs:

```kotlin
import org.jetbrains.compose.desktop.application.dsl.TargetFormat

plugins {
    alias(libs.plugins.kotlinMultiplatform)
    alias(libs.plugins.composeMultiplatform)
    alias(libs.plugins.composeCompiler)
    // alias(libs.plugins.androidApplication)
}

kotlin {
    // Android target (uncomment when needed)
    // androidTarget {
    //     compilations.all {
    //         compileTaskProvider.configure {
    //             compilerOptions {
    //                 jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    //             }
    //         }
    //     }
    // }

    // iOS targets (uncomment when needed)
    // listOf(
    //     iosArm64(),
    //     iosSimulatorArm64()
    // ).forEach { iosTarget ->
    //     iosTarget.binaries.framework {
    //         baseName = "ComposeApp"
    //         isStatic = true
    //     }
    // }

    // Desktop target (uncomment when needed)
    // jvm("desktop")

    sourceSets {
        commonMain.dependencies {
            implementation(compose.runtime)
            implementation(compose.foundation)
            implementation(compose.material3)
            implementation(compose.ui)
            implementation(compose.components.resources)
        }

        // androidMain.dependencies {
        //     implementation(compose.preview)
        //     implementation(libs.activity.compose)
        // }

        // val desktopMain by getting
        // desktopMain.dependencies {
        //     implementation(compose.desktop.currentOs)
        // }
    }
}

// Android configuration (uncomment when needed)
// android {
//     namespace = "com.example.app"
//     compileSdk = 35
//
//     defaultConfig {
//         applicationId = "com.example.app"
//         minSdk = 24
//         targetSdk = 35
//         versionCode = 1
//         versionName = "1.0.0"
//     }
//
//     compileOptions {
//         sourceCompatibility = JavaVersion.VERSION_17
//         targetCompatibility = JavaVersion.VERSION_17
//     }
// }

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

### Gradle Wrapper

Copy `gradlew`, `gradlew.bat`, and `gradle/wrapper/` from an existing
project. No global `gradle` is installed — bootstrap from an existing wrapper.

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
| `IPHONEOS_DEPLOYMENT_TARGET` | `15.0` (Compose 1.7.1 Skia minimum) |

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

export JAVA_HOME="${JAVA_HOME:-/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home}"
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

./gradlew :composeApp:$TASK
```

#### Gotcha: simulator caches scene configuration

When switching between scene-based and non-scene app lifecycle, **delete the
app from the simulator** before rebuilding. iOS caches the old scene
configuration and the new one won't take effect.

### Verification

After setup, verify compilation on all active targets:

```bash
# iOS
./gradlew :composeApp:compileKotlinIosSimulatorArm64

# Android
./gradlew :composeApp:assembleDebug

# Desktop (when enabled)
# ./gradlew :composeApp:compileKotlinDesktop
```

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
