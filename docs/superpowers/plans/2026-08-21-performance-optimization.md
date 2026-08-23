# ColdHot Performance Optimization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reduce ColdHot's hidden-panel CPU, wakeups, and private footprint without regressing threshold alerts, dynamic backgrounds, settings, or automatic updates, then produce a verified Direct local-test DMG.

**Architecture:** Keep sampling in `PerformanceMonitor`, but split its public observation surface into menu, panel, and settings projections. The sampler keeps an internal merged snapshot and uses a pure cadence planner to request only due metrics and explicit fan work; the panel projection flushes immediately when the panel becomes visible. Static/poster images are decoded to the largest Retina size ColdHot actually renders instead of their original stored dimensions.

**Tech Stack:** Swift 5, SwiftUI/AppKit, Combine, Darwin task/rusage APIs, IOKit/SMC, Xcode DirectRelease, shell-based Swift regression executables.

**Spec:** User-approved delegated performance brief in source task `01a01f85-9fd7-73d0-895a-40958e401fff`.

## Global Constraints

- Base commit is `eec997e` / ColdHot 1.5.0 (22); preserve all 1.5.0 GIF/video, three-level threshold, menu, settings, and Sparkle behavior.
- Work only in the existing clean linked worktree; do not modify or install over `/Applications/ColdHot.app`.
- Do not push, publish, notarize, or create a GitHub Release.
- Every production behavior change begins with a regression check that is observed failing for the intended reason.
- Hidden and visible benchmarks use the same seven metrics, two-second user interval, background asset, warm-up, duration, and task/rusage accounting.
- Deliver a Direct local-test package with an incremented version/build and verify mount, app signature, architecture, minimum macOS version, and isolated launch.

---

### Task 1: Deterministic performance fixture and baseline

**Files:**
- Create: `Scripts/PerformanceBenchmarkCheck.swift`
- Create: `.build/performance-optimization/baseline.json` (generated, not committed)

**Interfaces:**
- Consumes: real `PerformanceMonitor`, `DashboardView`, `PanelBackgroundStore`, and isolated `UserDefaults`.
- Produces: JSON containing hidden/open 60-second average and peak process CPU, whole-machine CPU, wakeups, resident bytes, physical footprint, private bytes, and monitor publication/sample counters.

- [ ] Compile the current source plus the benchmark fixture with `-D DIRECT` and a test `UpdateController`.
- [ ] Render the real dashboard in an `NSWindow`, warm it, hide it for 10 seconds, measure for 60 seconds, then show it, warm for 10 seconds, and measure for 60 seconds.
- [ ] Seed the fixture with seven enabled primary metrics, two-second sampling, completed onboarding, and the current user background store.
- [ ] Record the exact baseline JSON and ensure a second short smoke run produces finite, non-negative metrics.

### Task 2: Visibility-scoped publication projections

**Files:**
- Modify: `ColdHot/Monitoring/PerformanceMonitor.swift`
- Modify: `ColdHot/Views/DashboardView.swift`
- Modify: `ColdHot/Views/SettingsView.swift`
- Modify: `ColdHot/App/ColdHotApp.swift`
- Create: `Scripts/PerformancePublishingCheck.swift`

**Interfaces:**
- Produces: `PanelPerformanceProjection`, `MenuBarPerformanceProjection`, `SettingsPerformanceProjection`, `setPanelVisible(_:)`, and `setSettingsMonitoringActive(_:)`.
- Preserves: read-only compatibility accessors `snapshot`, `expandedMetric`, `activeThresholdAlerts`, `visibleThresholdAlert`, `trendHistory`, and `selfResourceSnapshot` for scripts.

- [ ] Add a failing check proving hidden sampling emits no panel projection changes, an alert-value/severity change emits one menu change, an equal menu alert emits none, opening the panel flushes the latest snapshot once, and unrelated settings pages emit no settings projection changes.
- [ ] Run the check and confirm failure because the projection/visibility APIs do not exist.
- [ ] Implement one coherent panel-state publish per sample only while visible, an equatable menu alert publish only on real change, and settings live-data publishes only while the About capability/resource area is active.
- [ ] Remove `@ObservedObject` observation of the whole monitor from `DashboardView`, `SettingsView`, and `MenuBarStatusLabel`; observe only the relevant projection in the smallest view scope.
- [ ] Run the focused check, existing threshold logic, menu renderer, panel, settings visual, and runtime checks.

### Task 3: Expanded-metric delayed sampling de-duplication

**Files:**
- Modify: `ColdHot/Monitoring/PerformanceMonitor.swift`
- Modify: `Scripts/PerformancePublishingCheck.swift`

**Interfaces:**
- Produces: equality-guarded `setExpandedMetric(_:)` and a cancelable/generation-guarded delayed refresh.

- [ ] Extend the focused check so repeated `nil`/same-metric calls do not publish or schedule another sample and a newer expansion cancels the previous 150ms refresh.
- [ ] Observe the failure against the current unconditional setter.
- [ ] Add the equality guard and one retained `DispatchWorkItem` (or equivalent generation token), cancel it on replacement and deinit, and publish expansion through the panel projection only when the value changes.
- [ ] Run focused and panel layout/background checks.

### Task 4: Cadence planner and demand-driven fans

**Files:**
- Modify: `ColdHot/Models/MetricKind.swift`
- Modify: `ColdHot/Models/PerformanceSnapshot.swift`
- Modify: `ColdHot/Monitoring/PerformanceMonitor.swift`
- Modify: `ColdHot/Monitoring/SystemSampler.swift`
- Create: `Scripts/SamplingDemandCheck.swift`

**Interfaces:**
- Produces: `SamplingCadencePlanner.request(...)`, `SamplingRequest.includesFans`, and `PerformanceSnapshot.merging(_:request:)`.
- Hidden cadence: CPU/network/memory use the user interval; GPU/disk at least every 5 seconds; temperature/fan thresholds at 5 seconds; battery at 30 seconds except enabled electrical-power thresholds at 5 seconds; visible panel requests enabled metrics and fans immediately.

- [ ] Add failing pure checks for hidden/visible metric due sets, immediate visibility refresh, threshold-only demand, 5-second fan threshold demand, 30-second battery demand, partial snapshot merging, and `SystemSampler` skipping its fan reader when `includesFans == false`.
- [ ] Run and verify RED for missing planner/fan request/merge APIs.
- [ ] Implement the pure planner, merge only fields actually requested, and inject a fan-reading closure into `SystemSampler` so the focused check exercises the real branch.
- [ ] Wire `PerformanceMonitor.sampleNow` to the planner while retaining threshold detail evaluation, alert rotation, trends, and immediate panel refresh.
- [ ] Run sampling, threshold, runtime, CPU/memory/HID, fan, and panel checks.

### Task 5: Bounded poster decoding

**Files:**
- Modify: `ColdHot/Models/PanelBackgroundStore.swift`
- Modify: `Scripts/PanelBackgroundCheck.swift`

**Interfaces:**
- Produces: a 960-pixel maximum decoded poster edge while keeping stored media, metadata stripping, GIF/video playback, crop math, and transactional rollback unchanged.

- [ ] Add a failing check that imports/loads a 1320-pixel image and asserts the decoded `posterImage` maximum pixel dimension is at most 960 while its aspect ratio and media kind remain correct.
- [ ] Observe failure at the current 1320/1600 decode path.
- [ ] Use ImageIO thumbnail decoding with transform and immediate caching at 960 pixels for both manifests and legacy images; align import maximum with the same bound only if existing import checks remain valid.
- [ ] Run panel, store, GIF conversion, playback, and settings visual checks.

### Task 6: Full verification and measured comparison

**Files:**
- Generate: `.build/performance-optimization/optimized.json`
- Generate: `.build/performance-optimization/report.md`

- [ ] Recompile the same benchmark fixture from optimized source and run identical hidden/open warm-up and 60-second windows.
- [ ] Report baseline versus optimized averages/peaks and memory values with exact units and accounting definitions.
- [ ] Run every existing script check plus the new focused checks.
- [ ] Run `xcodebuild` DirectRelease clean build and analyze with isolated DerivedData.
- [ ] Inspect `git diff --check`, version changes, and all modified files for unintended scope.

### Task 7: Versioned local-test DMG

**Files:**
- Modify: `Configurations/ReleaseCommon.xcconfig`
- Modify: `ColdHot.xcodeproj/project.pbxproj`
- Generate: `dist/local-test/1.5.1-23/ColdHot-Direct-1.5.1-23-local-test.dmg`

- [ ] Set test version/build to 1.5.1 (23), re-run version-sensitive settings rendering, clean build, and analyze.
- [ ] Run `Scripts/build-releases.sh local-test` only; do not invoke release/notary/update-feed modes.
- [ ] Verify SHA-256, ad-hoc runtime signature, DMG mount, 1.5.1/23 plist values, arm64+x86_64 architecture, macOS 14.0 minimum, and an isolated launch from the mounted app.
- [ ] Preserve the worktree and branch without merging or pushing.
