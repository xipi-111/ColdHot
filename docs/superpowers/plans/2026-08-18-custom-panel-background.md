# Custom Panel Background Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let ColdHot Direct users choose one local image as the full menu panel background, with an adjustable dark overlay and no work in the realtime sampling loop.

**Architecture:** `MonitorSettings` owns the small persisted preferences, while a new main-actor `PanelBackgroundStore` owns the app-managed PNG and its one-time `NSImage` cache. A reusable `PanelBackgroundView` renders material fallback, aspect-fill image and overlay; `ColdHotApp` injects the same store into the dashboard and settings views.

**Tech Stack:** Swift 5, SwiftUI, AppKit, ImageIO, UniformTypeIdentifiers, UserDefaults, standalone Swift verification scripts, Xcode 26.

**Spec:** `docs/panel-background-requirements.md`

## Global Constraints

- Minimum system version remains macOS 14.
- Only the `ColdHot Direct` scheme is maintained and released.
- Exactly one imported image is supported; no album rotation or network source.
- The imported longest edge is at most 1600 px and the app-owned copy is PNG.
- Dark overlay range is 0%–70%, with a 35% default.
- Image work must not run from the monitoring sampler or periodic refresh path.
- User content stays local and is never uploaded.

---

### Task 1: Persist panel appearance preferences

**Files:**
- Create: `Scripts/PanelBackgroundCheck.swift`
- Modify: `ColdHot/Models/MonitorSettings.swift`

**Interfaces:**
- Produces: `MonitorSettings.isPanelBackgroundEnabled: Bool`
- Produces: `MonitorSettings.panelBackgroundDimOpacity: Double`
- Produces: `setPanelBackgroundEnabled(_:)` and `setPanelBackgroundDimOpacity(_:)`

- [ ] **Step 1: Write the failing settings test**

Create `Scripts/PanelBackgroundCheck.swift` with an isolated UserDefaults suite and assertions that a new settings instance defaults to disabled/0.35, persists enabled/0.70, clamps -1 to 0 and 1 to 0.70, and resets to disabled/0.35.

```swift
import Foundation

@main
enum PanelBackgroundCheck {
    static func main() throws {
        checkSettingsPersistence()
        print("Panel background checks passed")
    }

    private static func checkSettingsPersistence() {
        let name = "com.xipiyoung.ColdHot.panel-background-check"
        guard let defaults = UserDefaults(suiteName: name) else { fatalError("defaults") }
        defaults.removePersistentDomain(forName: name)
        defer { defaults.removePersistentDomain(forName: name) }

        let initial = MonitorSettings(defaults: defaults)
        expect(!initial.isPanelBackgroundEnabled)
        expect(initial.panelBackgroundDimOpacity == 0.35)

        initial.setPanelBackgroundEnabled(true)
        initial.setPanelBackgroundDimOpacity(1)
        let restored = MonitorSettings(defaults: defaults)
        expect(restored.isPanelBackgroundEnabled)
        expect(restored.panelBackgroundDimOpacity == 0.70)

        restored.setPanelBackgroundDimOpacity(-1)
        expect(restored.panelBackgroundDimOpacity == 0)
        restored.reset()
        expect(!restored.isPanelBackgroundEnabled)
        expect(restored.panelBackgroundDimOpacity == 0.35)
    }

    private static func expect(_ condition: @autoclosure () -> Bool) {
        guard condition() else { fatalError("Check failed") }
    }
}
```

- [ ] **Step 2: Run the test to verify RED**

Run:

```bash
xcrun swiftc -D DIRECT ColdHot/App/BuildVariant.swift ColdHot/Models/MetricKind.swift ColdHot/Models/MonitorSettings.swift ColdHot/Models/PerformanceSnapshot.swift ColdHot/Models/ThresholdMetric.swift Scripts/PanelBackgroundCheck.swift -o .build/PanelBackgroundCheck
```

Expected: compilation fails because the four panel-background settings APIs do not exist.

- [ ] **Step 3: Implement the minimal settings API**

Add the following state, initialization, setters, reset values and private keys to `MonitorSettings`:

```swift
static let defaultPanelBackgroundDimOpacity = 0.35

@Published private(set) var isPanelBackgroundEnabled: Bool
@Published private(set) var panelBackgroundDimOpacity: Double

func setPanelBackgroundEnabled(_ enabled: Bool) {
    isPanelBackgroundEnabled = enabled
    defaults.set(enabled, forKey: Keys.isPanelBackgroundEnabled)
}

func setPanelBackgroundDimOpacity(_ opacity: Double) {
    let clamped = min(max(opacity, 0), 0.70)
    panelBackgroundDimOpacity = clamped
    defaults.set(clamped, forKey: Keys.panelBackgroundDimOpacity)
}
```

Initialization reads the Bool with a false fallback and clamps a stored finite Double; reset calls the two setters with false and 0.35.

- [ ] **Step 4: Run the test to verify GREEN**

Compile with the Step 2 command, then run `.build/PanelBackgroundCheck`.

Expected: `Panel background checks passed`.

- [ ] **Step 5: Commit the settings slice**

```bash
git add ColdHot/Models/MonitorSettings.swift Scripts/PanelBackgroundCheck.swift
git commit -m "feat: persist panel background preferences"
```

---

### Task 2: Import, downsample and cache the app-owned image

**Files:**
- Create: `ColdHot/Models/PanelBackgroundStore.swift`
- Modify: `Scripts/PanelBackgroundCheck.swift`
- Modify: `ColdHot.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: a user-selected local `URL`.
- Produces: `@MainActor final class PanelBackgroundStore: ObservableObject`.
- Produces: `init(directoryURL:fileManager:)`, `image`, `hasImage`, `importImage(from:) throws`, and `removeImage() throws`.

- [ ] **Step 1: Extend the script with failing image lifecycle tests**

Generate a real 2400×1200 PNG in a temporary test folder using CoreGraphics and ImageIO. Import it into a separate store directory, then assert using `CGImageSourceCopyPropertiesAtIndex` that `background.png` is 1600×800. Assert a second store loads the copy, an invalid import throws without replacing it, and `removeImage()` clears memory and disk.

```swift
let store = PanelBackgroundStore(directoryURL: storeDirectory)
try store.importImage(from: sourceURL)
expect(store.hasImage)
expect(pixelSize(of: store.fileURL) == CGSize(width: 1600, height: 800))

let restored = PanelBackgroundStore(directoryURL: storeDirectory)
expect(restored.hasImage)
do {
    try restored.importImage(from: invalidURL)
    fatalError("Invalid image import should fail")
} catch {}
expect(restored.hasImage)

try restored.removeImage()
expect(!restored.hasImage)
expect(!FileManager.default.fileExists(atPath: restored.fileURL.path))
```

- [ ] **Step 2: Run the test to verify RED**

Run the Task 1 compile command with `ColdHot/Models/PanelBackgroundStore.swift` added.

Expected: compilation fails because `PanelBackgroundStore.swift` and its APIs do not exist.

- [ ] **Step 3: Implement the image store**

Create a main-actor store that resolves `Application Support/ColdHot/PanelBackground`, publishes one cached `NSImage`, uses ImageIO thumbnail options with `kCGImageSourceThumbnailMaxPixelSize: 1600`, re-encodes to PNG using `CGImageDestination`, and writes atomically. Decode fully before writing so failed imports preserve the prior file. Expose `fileURL` internally for the real integration script.

```swift
@MainActor
final class PanelBackgroundStore: ObservableObject {
    static let maximumPixelDimension = 1600
    @Published private(set) var image: NSImage?
    let fileURL: URL
    var hasImage: Bool { image != nil }

    init(directoryURL: URL? = nil, fileManager: FileManager = .default) { /* resolve + load */ }
    func importImage(from sourceURL: URL) throws { /* scope + decode + PNG + atomic write */ }
    func removeImage() throws { /* remove owned copy + publish nil */ }
}
```

- [ ] **Step 4: Register the store in the Xcode project**

Add one PBX file reference under Models, one PBX build file, and one source build phase entry for `PanelBackgroundStore.swift`.

- [ ] **Step 5: Run the lifecycle test to verify GREEN**

Compile and run the script with `PanelBackgroundStore.swift` included.

Expected: it prints the success line and leaves no test files after deferred cleanup.

- [ ] **Step 6: Commit the storage slice**

```bash
git add ColdHot/Models/PanelBackgroundStore.swift ColdHot.xcodeproj/project.pbxproj Scripts/PanelBackgroundCheck.swift
git commit -m "feat: import and cache panel background image"
```

---

### Task 3: Render the full-panel background and expose settings controls

**Files:**
- Create: `ColdHot/Views/PanelBackgroundView.swift`
- Modify: `ColdHot/App/ColdHotApp.swift`
- Modify: `ColdHot/Views/DashboardView.swift`
- Modify: `ColdHot/Views/MetricRow.swift`
- Modify: `ColdHot/Views/SettingsView.swift`
- Modify: `ColdHot.xcodeproj/project.pbxproj`
- Modify: `Scripts/PanelBackgroundCheck.swift`

**Interfaces:**
- Consumes: the shared `PanelBackgroundStore` and the two `MonitorSettings` values.
- Produces: `PanelBackgroundView(image:isEnabled:dimOpacity:)`.
- Produces: Settings controls using SwiftUI `fileImporter` with `UTType.image`.

- [ ] **Step 1: Add a failing render check**

Extend `PanelBackgroundCheck.swift` with an `NSHostingView` rendering a solid-red image through `PanelBackgroundView` at 100×100. Cache the display into a bitmap and assert the center pixel is darker with `dimOpacity: 0.35` than with `dimOpacity: 0`, while both retain a red-dominant channel. This fails to compile before the view exists and catches removal of the overlay layer.

```swift
let clearPixel = renderCenterPixel(image: redImage, dimOpacity: 0)
let dimmedPixel = renderCenterPixel(image: redImage, dimOpacity: 0.35)
expect(clearPixel.red > 0.9 && clearPixel.red > clearPixel.green)
expect(dimmedPixel.red < clearPixel.red * 0.8)
expect(dimmedPixel.red > dimmedPixel.green)
```

- [ ] **Step 2: Run the script to verify RED**

Compile with `PanelBackgroundView.swift` added to the source list.

Expected: compilation fails because the view does not exist.

- [ ] **Step 3: Implement the reusable background view**

Render `regularMaterial` unconditionally as the fallback, then conditionally aspect-fill the cached `NSImage` and apply `Color.black.opacity(dimOpacity)`. Clamp the render opacity defensively and disable hit testing/accessibility for the decorative layer.

```swift
struct PanelBackgroundView: View {
    let image: NSImage?
    let isEnabled: Bool
    let dimOpacity: Double

    var body: some View {
        ZStack {
            Rectangle().fill(.regularMaterial)
            if isEnabled, let image {
                Image(nsImage: image).resizable().scaledToFill()
                Color.black.opacity(min(max(dimOpacity, 0), 0.70))
            }
        }
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
```

- [ ] **Step 4: Inject the shared store and cover the full dashboard**

Create `@StateObject private var panelBackgroundStore` in `ColdHotApp`, pass it to both scenes, replace Dashboard's existing material background with `PanelBackgroundView`, and change metric cards to a thin translucent material so photo-backed text remains readable.

- [ ] **Step 5: Add the settings section and file importer**

Add `@ObservedObject var panelBackgroundStore`, picker/error state, a top “面板背景” section with preview/toggle/0–70% slider, choose/replace/remove actions, `.fileImporter(allowedContentTypes: [.image])`, and an import error alert. Successful import enables the setting; removal disables it before deleting the app-owned copy.

- [ ] **Step 6: Register the view and verify GREEN**

Add `PanelBackgroundView.swift` to the Views PBX group/source phase, compile and run `PanelBackgroundCheck`, then build:

```bash
xcodebuild -project ColdHot.xcodeproj -scheme "ColdHot Direct" -configuration Debug -derivedDataPath .build/custom-background CODE_SIGNING_ALLOWED=NO build
```

Expected: script passes and Xcode reports `** BUILD SUCCEEDED **` without Swift warnings.

- [ ] **Step 7: Commit the UI slice**

```bash
git add ColdHot/App/ColdHotApp.swift ColdHot/Views/DashboardView.swift ColdHot/Views/MetricRow.swift ColdHot/Views/SettingsView.swift ColdHot/Views/PanelBackgroundView.swift ColdHot.xcodeproj/project.pbxproj Scripts/PanelBackgroundCheck.swift
git commit -m "feat: add custom menu panel background"
```

---

### Task 4: Prepare version 1.2.0 and perform full verification

**Files:**
- Modify: `ColdHot.xcodeproj/project.pbxproj`
- Modify: `Configurations/ReleaseCommon.xcconfig`
- Modify: `README.md`
- Create: `RELEASE-NOTES-1.2.0.md`

**Interfaces:**
- Consumes: the complete background feature.
- Produces: Direct app metadata `1.2.0 (8)` and user-facing documentation.

- [ ] **Step 1: Update documentation and version metadata**

Add the custom full-panel background capability and local/downsampled storage note to README. Create release notes describing the background chooser, adjustable readability overlay and local-only handling. Change Debug and Release target values and `Configurations/ReleaseCommon.xcconfig` to `MARKETING_VERSION = 1.2.0` and `CURRENT_PROJECT_VERSION = 8`, so DirectRelease receives the same metadata.

- [ ] **Step 2: Run all standalone checks**

Compile and run:

```bash
.build/ThresholdLogicCheck
.build/FanSpinnerCenterCheck .build/fan-center.png
.build/PanelBackgroundCheck
```

Expected: all three print their success messages.

- [ ] **Step 3: Build and analyze the Direct scheme**

Run Debug build and DirectRelease analyze with code signing disabled.

```bash
xcodebuild -project ColdHot.xcodeproj -scheme "ColdHot Direct" -configuration DirectRelease -derivedDataPath .build/custom-background-analyze CODE_SIGNING_ALLOWED=NO analyze
```

Expected: `** ANALYZE SUCCEEDED **`, no new compile errors or analyzer findings.

- [ ] **Step 4: Perform manual visual and interaction QA**

Launch the isolated Debug app, choose a portrait and a landscape image, verify whole-panel aspect-fill, overlay adjustment, readable cards, immediate toggle behavior, replace/remove operations, default reset behavior, and material fallback after deleting the app-owned cache in a controlled test profile. Confirm Activity Monitor shows no periodic image file access or extra worker process during metric refresh.

- [ ] **Step 5: Review the diff and commit release metadata**

Run `git diff --check`, inspect `git diff main...HEAD`, confirm only the approved feature and documentation changed, then commit:

```bash
git add ColdHot.xcodeproj/project.pbxproj Configurations/ReleaseCommon.xcconfig README.md RELEASE-NOTES-1.2.0.md
git commit -m "chore: prepare ColdHot 1.2.0"
```

---

## Self-Review

- Spec coverage: settings, full-panel rendering, overlay range/default, local-only copy, downsampling, caching, failures, reset/remove semantics, versioning and Direct-only distribution each map to Tasks 1–4.
- Placeholder scan: all implementation steps contain concrete APIs, commands and expected results.
- Type consistency: both views consume the same `PanelBackgroundStore`; settings API names and opacity range are identical across tasks; the test script exercises real UserDefaults, files, ImageIO and SwiftUI rendering without mocks.
