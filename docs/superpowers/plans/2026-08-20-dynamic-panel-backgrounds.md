# Dynamic Panel Backgrounds Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add locally stored GIF and video menu-panel backgrounds with visibility-aware playback, separate menu/preview audio behavior, Reduce Motion fallbacks, and transactional failure recovery.

**Architecture:** Introduce a typed background asset and versioned manifest, convert GIFs once through ImageIO and AVAssetWriter, preserve imported video files, and commit prepared media transactionally through `PanelBackgroundStore`. Use separate AVFoundation playback coordinators for the real menu and Settings preview; SwiftUI controls visibility, mute policy, crop transform, poster fallback, and user messaging.

**Tech Stack:** Swift 5, SwiftUI, AppKit, AVFoundation, CoreVideo, CoreGraphics, ImageIO, UniformTypeIdentifiers, UserDefaults, Xcode 17/macOS 26 SDK with deployment target macOS 14.0.

**Spec:** `docs/superpowers/specs/2026-08-19-dynamic-panel-backgrounds-design.md`

## Global Constraints

- Target release is **1.4.0 (20)**; do not publish or notarize until local installation acceptance passes.
- Keep deployment target macOS 14.0 and do not add third-party media dependencies.
- GIF input limit is exactly 100 MB; video input limit is exactly 1 GB; boundary files are accepted and files one byte above are rejected.
- Do not impose a media-duration limit.
- Imported content remains in `~/Library/Application Support/ColdHot/PanelBackground/` and is never uploaded.
- GIF becomes a silent looping MP4; video retains its original container, codec, dimensions, frame rate, and audio tracks.
- Static images, GIFs, and video reuse existing zoom, position, dimming, card, text, and progress settings.
- Real-menu audio persists; Settings preview audio never persists and resets on leaving Appearance or closing Settings.
- Reduce Motion means poster-only, paused playback, no audio, and the approved messages.
- Every production behavior starts with a failing check and follows RED → GREEN before refactoring.
- Preserve the user-owned untracked `AGENTS.md`; never stage or modify it.

---

### Task 1: Asset contract, import limits, and persisted menu audio

**Files:**
- Create: `ColdHot/Models/PanelBackgroundAsset.swift`
- Modify: `ColdHot/Models/MonitorSettings.swift`
- Modify: `ColdHot.xcodeproj/project.pbxproj`
- Create: `Scripts/DynamicBackgroundPolicyCheck.swift`

**Interfaces:**
- Consumes: existing `MonitorSettings(defaults:)` persistence and panel transform state.
- Produces: `PanelBackgroundMediaKind`, `PanelBackgroundManifest`, `PanelBackgroundAsset`, `PanelBackgroundImportLimits`, `MonitorSettings.isPanelBackgroundAudioEnabled`, `setPanelBackgroundAudioEnabled(_:)`, and `didReplacePanelBackground(kind:)`.

- [ ] **Step 1: Write the failing policy check**

Create an isolated-defaults executable containing these assertions:

```swift
expect(PanelBackgroundImportLimits.maximumGIFBytes == 100 * 1_024 * 1_024)
expect(PanelBackgroundImportLimits.maximumVideoBytes == 1_024 * 1_024 * 1_024)
expect(PanelBackgroundImportLimits.acceptsGIF(byteCount: 100 * 1_024 * 1_024))
expect(!PanelBackgroundImportLimits.acceptsGIF(byteCount: 100 * 1_024 * 1_024 + 1))
expect(PanelBackgroundImportLimits.acceptsVideo(byteCount: 1_024 * 1_024 * 1_024))
expect(!PanelBackgroundImportLimits.acceptsVideo(byteCount: 1_024 * 1_024 * 1_024 + 1))

let settings = MonitorSettings(defaults: defaults)
expect(!settings.isPanelBackgroundAudioEnabled)
settings.setPanelBackgroundAudioEnabled(true)
expect(MonitorSettings(defaults: defaults).isPanelBackgroundAudioEnabled)
settings.didReplacePanelBackground(kind: .staticImage)
expect(settings.isPanelBackgroundAudioEnabled)
settings.didReplacePanelBackground(kind: .video)
expect(!settings.isPanelBackgroundAudioEnabled)
settings.setPanelBackgroundAudioEnabled(true)
settings.didReplacePanelBackground(kind: .convertedGIF)
expect(settings.isPanelBackgroundAudioEnabled)
settings.didRemovePanelBackground()
expect(!settings.isPanelBackgroundAudioEnabled)
```

This catches limit drift, lost persistence, resetting sound for non-video replacements, and failure to mute a new/removed video.

- [ ] **Step 2: Compile to verify RED**

Run:

```bash
mkdir -p .build/dynamic-backgrounds
xcrun swiftc ColdHot/App/BuildVariant.swift ColdHot/Models/MetricKind.swift \
  ColdHot/Models/ThresholdMetric.swift ColdHot/Models/MonitorSettings.swift \
  Scripts/DynamicBackgroundPolicyCheck.swift \
  -o .build/dynamic-backgrounds/DynamicBackgroundPolicyCheck
```

Expected: missing media types, limits, and audio APIs fail compilation.

- [ ] **Step 3: Add the exact asset contracts**

Create:

```swift
enum PanelBackgroundMediaKind: String, Codable, Equatable {
    case staticImage, convertedGIF, video
    var isDynamic: Bool { self != .staticImage }
}

struct PanelBackgroundManifest: Codable, Equatable {
    static let currentSchemaVersion = 1
    let schemaVersion: Int
    let generationID: String
    let kind: PanelBackgroundMediaKind
    let mediaFilename: String
    let posterFilename: String?
    let originalTypeIdentifier: String
    let hasAudio: Bool
}

struct PanelBackgroundAsset: Identifiable {
    let id: String
    let kind: PanelBackgroundMediaKind
    let posterImage: NSImage
    let mediaURL: URL?
    let hasAudio: Bool
    var isDynamic: Bool { kind.isDynamic }
}

enum PanelBackgroundImportLimits {
    static let maximumGIFBytes: Int64 = 100 * 1_024 * 1_024
    static let maximumVideoBytes: Int64 = 1_024 * 1_024 * 1_024
    static func acceptsGIF(byteCount: Int64) -> Bool {
        byteCount >= 0 && byteCount <= maximumGIFBytes
    }
    static func acceptsVideo(byteCount: Int64) -> Bool {
        byteCount >= 0 && byteCount <= maximumVideoBytes
    }
}
```

Add the file to the Models PBX group and Sources build phase.

- [ ] **Step 4: Persist the real-menu sound setting**

Add `@Published private(set) var isPanelBackgroundAudioEnabled: Bool`, initialize it from `UserDefaults` with default `false`, add its key and setter, and replace the old replacement callback with:

```swift
func didReplacePanelBackground(kind: PanelBackgroundMediaKind) {
    resetPanelBackgroundTransform()
    setPanelBackgroundEnabled(true)
    if kind == .video { setPanelBackgroundAudioEnabled(false) }
}
```

`didRemovePanelBackground()` and the existing reset-defaults path must call `setPanelBackgroundAudioEnabled(false)`.

Keep a temporary compatibility wrapper so the branch still builds before Task 6 migrates Settings:

```swift
func didReplacePanelBackgroundImage() {
    didReplacePanelBackground(kind: .staticImage)
}
```

- [ ] **Step 5: Verify GREEN and commit**

Compile with `PanelBackgroundAsset.swift`, run the check, expect `Dynamic background policy checks passed`, then:

```bash
git add ColdHot/Models/PanelBackgroundAsset.swift ColdHot/Models/MonitorSettings.swift \
  ColdHot.xcodeproj/project.pbxproj Scripts/DynamicBackgroundPolicyCheck.swift
git diff --cached --check
git commit -m "feat: define dynamic background policy"
```

---

### Task 2: Deterministic GIF-to-MP4 conversion

**Files:**
- Create: `ColdHot/Media/GIFVideoConverter.swift`
- Create: `Scripts/DynamicBackgroundTestMedia.swift`
- Create: `Scripts/GIFVideoConversionCheck.swift`
- Modify: `ColdHot.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: Task 1 limits.
- Produces: `GIFVideoConversionResult` and `GIFVideoConverter.convert(sourceURL:destinationURL:) async throws`.

- [ ] **Step 1: Write real two-frame GIF fixtures and a failing check**

In `DynamicBackgroundTestMedia.swift`, implement `makeTwoFrameGIF(at:)` with ImageIO, 32×24 red/blue frames, and 0.10/0.25-second delays. Keep the helper free of `@main`.

The async check must convert it, then assert:

```swift
precondition(result.frameCount == 2)
precondition(abs(result.duration.seconds - 0.35) < 0.06)
precondition(result.displaySize == CGSize(width: 32, height: 24))
let asset = AVURLAsset(url: mp4URL)
precondition(try await asset.loadTracks(withMediaType: .video).count == 1)
precondition(try await asset.loadTracks(withMediaType: .audio).isEmpty)
precondition(try await asset.load(.isPlayable))
```

Decode images near 0.03 and 0.20 seconds with `AVAssetImageGenerator`; assert the first is red-dominant and the second blue-dominant so the test cannot pass with a static first frame.

- [ ] **Step 2: Compile to verify RED**

Compile the model, fixture, and check. Expected: `GIFVideoConverter` is missing.

- [ ] **Step 3: Implement timeline extraction and MP4 writing**

Expose:

```swift
struct GIFVideoConversionResult {
    let frameCount: Int
    let duration: CMTime
    let displaySize: CGSize
}

struct GIFVideoConverter {
    static let maximumPixelDimension = 1_600
    static let minimumFrameDuration = 0.02
    func convert(sourceURL: URL, destinationURL: URL) async throws
        -> GIFVideoConversionResult
}
```

Read unclamped delay before clamped delay; replace missing, non-finite, zero, or negative delays with 0.02 seconds. Decode every composited frame with ImageIO and scale the canvas to a maximum edge of 1,600 pixels.

Use `AVAssetWriter(fileType:.mp4)`, H.264, 32BGRA pixel buffers, and timescale 600. Fill transparent pixels with the GIF logical background or black when absent, draw each frame, and append at accumulated time. Append the final frame once more at the accumulated end time so the last delay contributes to duration. On any non-completed writer status, delete partial output and throw a localized conversion error.

- [ ] **Step 4: Verify GREEN, target build, and commit**

Run the timing/color/playability/no-audio check, add the converter to a new Media PBX group/Sources, run unsigned DirectRelease build, then:

```bash
git add ColdHot/Media/GIFVideoConverter.swift Scripts/DynamicBackgroundTestMedia.swift \
  Scripts/GIFVideoConversionCheck.swift ColdHot.xcodeproj/project.pbxproj
git diff --cached --check
git commit -m "feat: convert GIF backgrounds to video"
```

---

### Task 3: Transactional static, GIF, and video storage

**Files:**
- Create: `ColdHot/Media/PanelBackgroundMediaImporter.swift`
- Modify: `ColdHot/Models/PanelBackgroundStore.swift`
- Modify: `ColdHot.xcodeproj/project.pbxproj`
- Create: `Scripts/DynamicBackgroundStoreCheck.swift`
- Modify: `Scripts/DynamicBackgroundTestMedia.swift`
- Modify: `Scripts/PanelBackgroundCheck.swift`

**Interfaces:**
- Consumes: Task 1 asset/manifest types and Task 2 converter.
- Produces: `PanelBackgroundPreparedImport`, `PanelBackgroundMediaImporter.prepareImport(from:in:) async throws`, `PanelBackgroundStore.asset`, `hasBackground`, `importBackground(from:) async throws`, and `removeBackground() throws`.

- [ ] **Step 1: Add failing real-file store checks**

Extend test media with a silent H.264 video and an audio-video MOV. Generate PCM CAF through `AVAudioFile`, combine it with silent video using `AVMutableComposition`, and export MOV—no fake metadata.

The store check must prove:

- legacy `background.png` loads as `.staticImage` without a manifest;
- static import writes schema 1 manifest;
- GIF import publishes `.convertedGIF`, MP4, poster, and `hasAudio == false`;
- silent/audio video publish `.video` with correct audio detection and preserve extension;
- corrupted replacement throws and preserves prior asset ID, manifest, and files;
- removal deletes media, poster, manifest, legacy image, and staging files;
- sparse files one byte above both limits are rejected before copying.

- [ ] **Step 2: Compile to verify RED**

Compile store, asset, converter, fixtures, and the new check. Expected: importer and async store APIs are missing.

- [ ] **Step 3: Implement prepared imports and localized errors**

Create:

```swift
struct PanelBackgroundPreparedImport {
    let kind: PanelBackgroundMediaKind
    let mediaURL: URL
    let posterURL: URL?
    let originalTypeIdentifier: String
    let hasAudio: Bool
}

enum PanelBackgroundImportError: LocalizedError {
    case gifTooLarge, videoTooLarge, unreadableMedia, missingVideoTrack
    case unsupportedVideo, gifConversionFailed, unableToCreatePoster, unableToWrite
}

struct PanelBackgroundMediaImporter {
    func prepareImport(from sourceURL: URL, in stagingDirectory: URL) async throws
        -> PanelBackgroundPreparedImport
}
```

Resolve UTType from resource values, extension, then ImageIO. Treat only GIF as animated; other images use the existing 1,600-pixel PNG thumbnail path. Check size before reading/copying. Validate video with `AVURLAsset.isPlayable` and a real video track, detect audio from audio tracks, copy original bytes, and make a transformed first-frame PNG poster.

- [ ] **Step 4: Make PanelBackgroundStore manifest-backed and transactional**

Expose:

```swift
@Published private(set) var asset: PanelBackgroundAsset?
var image: NSImage? { asset?.posterImage }
var hasImage: Bool { asset != nil }
var hasBackground: Bool { asset != nil }
func importBackground(from sourceURL: URL) async throws
func removeBackground() throws
```

Hold security-scoped access for the full async operation. Prepare inside `staging-<UUID>`, move output to unique generation filenames, and atomically write `manifest.json` last. Publish only after reloading committed files; then delete the previous generation and legacy PNG. Failure deletes only staging/unreferenced new files and preserves the previous manifest/asset. Startup loads schema 1 or falls back to legacy `background.png`, and cleans only `staging-` directories.

- [ ] **Step 5: Verify GREEN, update old checks, and commit**

Migrate existing tests from `importImage`/`removeImage` to async `importBackground`/`removeBackground`. Run store and panel checks plus Direct build, then:

```bash
git add ColdHot/Media/PanelBackgroundMediaImporter.swift ColdHot/Models/PanelBackgroundStore.swift \
  ColdHot.xcodeproj/project.pbxproj Scripts/DynamicBackgroundStoreCheck.swift \
  Scripts/DynamicBackgroundTestMedia.swift Scripts/PanelBackgroundCheck.swift
git diff --cached --check
git commit -m "feat: store dynamic backgrounds transactionally"
```

---

### Task 4: Visibility-aware looping player and poster fallback

**Files:**
- Create: `ColdHot/Media/PanelBackgroundPlaybackController.swift`
- Create: `ColdHot/Views/PanelBackgroundPlayerView.swift`
- Modify: `ColdHot/Views/PanelBackgroundView.swift`
- Modify: `ColdHot.xcodeproj/project.pbxproj`
- Create: `Scripts/DynamicBackgroundPlaybackCheck.swift`

**Interfaces:**
- Consumes: Task 3 `PanelBackgroundAsset`.
- Produces: `PanelBackgroundPlaybackIntent`, controller configure/update/pause/reset APIs, and AVPlayerLayer rendering.

- [ ] **Step 1: Write failing pure-policy and real-player checks**

Assert this matrix:

```swift
let active = PanelBackgroundPlaybackIntent(
    isEnabled: true, isVisible: true, reduceMotion: false,
    audioRequested: true, assetIsDynamic: true, assetHasAudio: true
)
precondition(active.shouldPlay && !active.shouldMute)
let hidden = active.copy(isVisible: false)
precondition(!hidden.shouldPlay && hidden.shouldMute)
let reduced = active.copy(reduceMotion: true)
precondition(!reduced.shouldPlay && reduced.shouldMute)
precondition(reduced.shouldShowReduceMotionMessage)
```

`copy` is test-only. With a real two-second video: configure and play; hide and prove media time advances less than 50 ms over 300 ms; reactivate and prove it resumes; configure a second ID and prove replacement starts near zero; reset and prove no item/looper remains. Configure a deliberately invalid dynamic URL and prove the controller pauses, publishes one error, and does not continuously recreate the item.

- [ ] **Step 2: Compile to verify RED**

Expected: playback intent/controller types are missing.

- [ ] **Step 3: Implement intent and MainActor controller**

Use:

```swift
struct PanelBackgroundPlaybackIntent: Equatable {
    let isEnabled, isVisible, reduceMotion, audioRequested: Bool
    let assetIsDynamic, assetHasAudio: Bool
    var shouldPlay: Bool { isEnabled && isVisible && !reduceMotion && assetIsDynamic }
    var shouldMute: Bool { !shouldPlay || !assetHasAudio || !audioRequested }
    var shouldShowReduceMotionMessage: Bool {
        isEnabled && assetIsDynamic && reduceMotion
    }
}
```

The controller owns one `AVQueuePlayer` and optional `AVPlayerLooper`. `configure(asset:)` is idempotent for the same ID and replaces/clears on change. `update(intent:)` sets mute before play/pause and never seeks on visibility pause. Observe player-item status: failure pauses and publishes `playbackErrorMessage`, leaving the poster visible. Retry at most once when the same asset transitions from hidden to visible; asset change clears the retry state. `reset()` disables the looper, removes items/observers, clears error/retry state and active ID. Do not add a display timer.

- [ ] **Step 4: Implement noninteractive player layer and unified transform**

`PanelBackgroundPlayerView` uses a layer-backed AppKit view with `AVPlayerLayer`, `.resizeAspectFill`, `hitTest == nil`, identity-based player updates, and player clearing during dismantle.

Refactor `PanelBackgroundView` to receive asset, controller, and intent. Render poster first and overlay the player only for a configured dynamic asset. Compute one `PanelBackgroundTransform` from `posterImage.size` and apply it to both poster and player, then retain the dim layer. Keep the current `init(image:isEnabled:dimOpacity:zoom:position:)` as a static-only compatibility initializer until Tasks 5–6 migrate every production caller; this keeps Task 4 independently buildable.

- [ ] **Step 5: Verify GREEN, target build, and commit**

Run playback and existing panel checks, add both files to PBX Sources, build Direct, then:

```bash
git add ColdHot/Media/PanelBackgroundPlaybackController.swift \
  ColdHot/Views/PanelBackgroundPlayerView.swift ColdHot/Views/PanelBackgroundView.swift \
  ColdHot.xcodeproj/project.pbxproj Scripts/DynamicBackgroundPlaybackCheck.swift
git diff --cached --check
git commit -m "feat: play dynamic backgrounds on demand"
```

---

### Task 5: Real menu lifecycle, persisted sound button, and Reduce Motion

**Files:**
- Modify: `ColdHot/App/ColdHotApp.swift`
- Modify: `ColdHot/Views/DashboardView.swift`
- Modify: `ColdHot/Views/PanelAppearancePreview.swift`
- Modify: `Scripts/PanelBackgroundCheck.swift`

**Interfaces:**
- Consumes: app-scoped playback controller, store asset, persisted audio, and Reduce Motion.
- Produces: menu lifecycle playback, sound button beside Settings, and “减少动态效果已开启”.

- [ ] **Step 1: Write failing menu presentation checks**

Using the existing accessibility reporter pattern, assert:

- `panel-background-audio-toggle` exists only for audio video;
- its label toggles between “开启视频背景声音” and “关闭视频背景声音”;
- action persists the setting;
- GIF/static/silent video omit the button;
- Reduce Motion adds `panel-reduce-motion-message`, disables audio, and yields paused/muted intent;
- Dashboard disappearance sets visibility false without changing the persisted preference.

- [ ] **Step 2: Run to verify RED**

Compile the expanded panel check. Expected: missing controller constructor and identifiers fail.

- [ ] **Step 3: Own and drive the menu player**

Add an app-scoped `@StateObject PanelBackgroundPlaybackController` in `ColdHotApp` and pass it only to Dashboard. In Dashboard, read `accessibilityReduceMotion`, track visible state with appear/disappear, derive the complete intent, and update on asset ID, enabled, visible, Reduce Motion, or audio changes. Menu close pauses without reset; replacement/removal resets.

- [ ] **Step 4: Add approved controls/messages**

Immediately after Settings in the left footer group, show an icon-only plain button only for `.video && hasAudio`. Use `speaker.wave.2.fill`/`speaker.slash.fill`, identifier `panel-background-audio-toggle`, approved labels/help, and disable under Reduce Motion without rewriting preference.

Directly above the footer divider, only for an enabled dynamic asset under Reduce Motion, render “减少动态效果已开启” with caption-secondary styling and identifier `panel-reduce-motion-message`.

- [ ] **Step 5: Migrate preview constructor, verify, and commit**

Add a new `PanelAppearancePreview` initializer that accepts asset/controller/intent and migrate Dashboard-owned usage, while retaining the existing static-image initializer used by Settings until Task 6. Interactive preview audio follows in Task 6. Run panel/layout/runtime checks and Direct build, then:

```bash
git add ColdHot/App/ColdHotApp.swift ColdHot/Views/DashboardView.swift \
  ColdHot/Views/PanelAppearancePreview.swift Scripts/PanelBackgroundCheck.swift
git diff --cached --check
git commit -m "feat: control menu background audio"
```

---

### Task 6: Settings import, temporary preview audio, and messages

**Files:**
- Modify: `ColdHot/Views/SettingsView.swift`
- Modify: `ColdHot/Views/PanelAppearancePreview.swift`
- Modify: `Scripts/SettingsVisualCheck.swift`
- Modify: `Scripts/PanelBackgroundCheck.swift`

**Interfaces:**
- Consumes: async store import, independent controller, selected page, asset audio metadata, Reduce Motion.
- Produces: unified picker/progress/errors, temporary preview audio reset, messages, and crop-compatible dynamic preview.

- [ ] **Step 1: Write failing Settings behavior and visual checks**

Assert:

- picker copy says “自定义背景”, “选择背景…”/“更换背景…”, and 图片、GIF 与视频;
- audio-video exposes `settings-preview-audio-toggle` beside “菜单面板真实范围”;
- static/GIF/silent video omit it;
- audio-video shows “仅本次预览，离开后恢复静音”;
- tab switch, Settings disappearance, asset replacement, and removal reset preview sound;
- Reduce Motion shows “减少动态效果已开启，动态背景与声音已暂停”, disables audio, and produces poster-only intent;
- a corrupt or unsupported selection preserves the prior asset, enabled state, crop values, and real-menu audio preference;
- 920×720 and 860×680 Aqua/Dark screenshots do not clip title-row button, progress, or messages.

- [ ] **Step 2: Run checks to verify RED**

Run the Settings visual executable. Expected: identifiers, copy, and reset assertions fail.

- [ ] **Step 3: Implement async unified import**

Allow `[.image, .movie, .mpeg4Movie, .quickTimeMovie]`. Add processing state, independent preview-audio state, and Settings-owned playback controller. In a MainActor Task, set processing true, await `importBackground`, call `didReplacePanelBackground(kind:)`, then reset processing/audio. Disable select/remove during processing and show `ProgressView("正在处理动态背景…")`. Use alert title “无法设置背景” and importer-localized error text; cancellation stays silent.

Update the existing remove action to call `panelBackgroundStore.removeBackground()` followed by `settings.didRemovePanelBackground()` only after filesystem removal succeeds; failure keeps the current asset and settings.

After all call sites use `didReplacePanelBackground(kind:)`, remove the temporary `didReplacePanelBackgroundImage()` compatibility wrapper introduced in Task 1.

- [ ] **Step 4: Update resource labels and crop behavior**

Map kinds to “自定义图片”, “动态 GIF”, or “视频背景”; rename buttons to background wording. Keep all transform/readability controls for every kind. Drag calculations use `asset.posterImage.size` so poster and playback crop identically.

- [ ] **Step 5: Implement independent temporary preview sound**

Put the preview button in the title HStack, only for audio video, with identifier `settings-preview-audio-toggle`, speaker icon, and “开启/关闭预览声音” label. Show “仅本次预览，离开后恢复静音”. Reset and pause on leaving Appearance, root disappearance, asset ID change, replacement, or removal. Never read/write the real-menu audio preference. Remove the old static-only `PanelAppearancePreview` and `PanelBackgroundView` compatibility initializers after the final production call site is migrated.

- [ ] **Step 6: Add Reduce Motion preview state**

For enabled dynamic assets under Reduce Motion, display the approved longer message, disable preview sound, mute/pause intent, and retain poster dragging/static controls.

- [ ] **Step 7: Verify GREEN and commit**

Render all 20 Settings screenshots plus audio-video and Reduce Motion fixtures; run store/panel checks; confirm stale picker copy is absent. Then:

```bash
git add ColdHot/Views/SettingsView.swift ColdHot/Views/PanelAppearancePreview.swift \
  Scripts/SettingsVisualCheck.swift Scripts/PanelBackgroundCheck.swift
git diff --cached --check
git commit -m "feat: preview dynamic backgrounds in settings"
```

---

### Task 7: Resource verification, version 1.4.0, and installable package

**Files:**
- Modify: `Configurations/ReleaseCommon.xcconfig`
- Modify: `ColdHot.xcodeproj/project.pbxproj`
- Create: `RELEASE-NOTES-1.4.0.md`
- Modify: a check only after reproducing a newly discovered gap
- Generate: `dist/local-test/1.4.0-20/ColdHot-Direct-1.4.0-20-local-test.dmg`

**Interfaces:**
- Consumes: Tasks 1–6 and all regression scripts.
- Produces: verified 1.4.0 (20), local DMG, installed runtime evidence, and release handoff.

- [ ] **Step 1: Run the complete source/behavior suite fresh**

Freshly compile and run: ProcessCPUAccounting, MemoryAccounting, HID ownership, threshold logic, panel layout, fan center, panel background, dynamic policy, GIF conversion, dynamic store, dynamic playback, Settings visual, and performance runtime checks. Record every exit code; skip none silently.

- [ ] **Step 2: Verify hidden-player resources with real media**

With a known 720p/30fps ten-second video: play 30 seconds, hide 60 seconds, and prove paused status, less than 50 ms media-time movement, no visible player layer, CPU/wakeups returning to static baseline, no instance growth after 20 open/close cycles, and no staging leftovers. Report codec, dimensions, frame rate, CPU, memory, and wakeups without generalizing to arbitrary 4K codecs.

- [ ] **Step 3: Run installed UI acceptance**

Verify static compatibility, GIF timing, matching crop, menu sound persistence, new-video mute reset, preview mute reset, both Reduce Motion messages, sound-button eligibility, failure rollback, and full removal. Any defect gets a failing check before a fix.

- [ ] **Step 4: Bump and verify metadata**

Set both config and PBX fallback values:

```xcconfig
MARKETING_VERSION = 1.4.0
CURRENT_PROJECT_VERSION = 20
```

Clean-build Direct and verify Info.plist values, macOS 14.0, and arm64/x86_64 Universal binary.

- [ ] **Step 5: Add focused release notes**

Create:

```markdown
# ColdHot 1.4.0

- 自定义菜单背景新增 GIF、MP4、MOV 与 M4V 支持。
- 动态背景仅在菜单或外观预览可见时播放，关闭后立即暂停以降低资源占用。
- 带声音的视频可在菜单底部独立控制声音；设置预览声音离开后自动恢复静音。
- 开启系统“减少动态效果”时自动显示静态封面并暂停动画与声音。
- 背景导入采用本机事务处理，失败或超限不会替换当前背景。
```

- [ ] **Step 6: Build and verify the local package**

Run clean unsigned Direct build and `./Scripts/build-releases.sh local-test`. Mount the 1.4.0-20 DMG, run strict deep code-sign verification, verify Info.plist, SHA256, then detach.

- [ ] **Step 7: Request independent review and resolve findings**

Ask specifically about security-scope lifetime, rollback, GIF timing, looper cleanup, audio leakage, Reduce Motion, preview reset, limits, legacy migration, and test validity. Fix every Critical/Important finding with RED → GREEN and request focused rereview.

- [ ] **Step 8: Commit release metadata and final fixes**

```bash
git add Configurations/ReleaseCommon.xcconfig ColdHot.xcodeproj/project.pbxproj \
  RELEASE-NOTES-1.4.0.md ColdHot Scripts
git reset -- AGENTS.md 2>/dev/null || true
git diff --cached --check
git commit -m "feat: release dynamic panel backgrounds"
```

- [ ] **Step 9: Install only after explicit approval**

Present the verified DMG and wait for “安装”. Then quit only ColdHot, move the current app to a uniquely named recoverable Trash backup, install, launch, and report version/build, PID, backup path, CPU, and memory. Never delete the backup.
