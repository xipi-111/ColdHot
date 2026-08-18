# Apple Music-Style Settings Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the ColdHot settings window with the user-approved A1 Apple Music-style navigation shell, ColdHot green accent, 920×720 default size, and consistent low-chrome settings sections while preserving every existing setting and behavior.

**Architecture:** Add one focused `SettingsChrome.swift` unit that owns navigation, layout metrics, materials, section surfaces, accessibility-aware transitions, and scaled preview presentation. Keep all bindings and business actions in `SettingsView.swift`, replacing only its default `NavigationSplitView` and grouped Forms. Extend the existing executable visual check so geometry, titlebar persistence, selection logic, five page states, and screenshot output are verified against the real SwiftUI view.

**Tech Stack:** Swift 5, SwiftUI, AppKit, macOS 14 minimum deployment, macOS 26 `glassEffect`, pre-macOS-26 `NSVisualEffectView.Material.sidebar`, existing script-based Swift checks, Xcode 26.6.

**Spec:** `docs/superpowers/specs/2026-08-18-apple-music-settings-redesign.md`

## Global Constraints

- Keep `MACOSX_DEPLOYMENT_TARGET = 14.0`.
- Default settings content size is exactly 920×720; minimum content size is exactly 860×680.
- Sidebar width is exactly 204pt, page title is 34pt, section title is 13pt semibold, section row height is 40pt, and sidebar row height is 32pt.
- Use ColdHot green for selected sidebar icon/text; never use Apple Music pink or a system-blue full-width selection.
- Use glass only for the navigation layer; content surfaces remain quiet and opaque/translucent system surfaces.
- Preserve the logical 370pt `PanelAppearancePreview` canvas and crop; scale only its presentation in settings.
- Preserve all existing settings, bindings, monitoring, notification, update, Dock, file-import, error, and privacy behaviors.
- Respect Reduce Transparency and Reduce Motion.
- Do not publish GitHub or produce a public release in this plan.
- Preserve unrelated pre-existing working-tree changes. Before every commit, inspect `git diff --cached` and unstage any unrelated path or hunk.

## File Structure

- Create `ColdHot/Views/SettingsChrome.swift`: `SettingsPage`, exact layout metrics, keyboard selection policy, custom shell/sidebar, macOS-version material switching, reusable settings section/row surfaces, page transition host, and scaled preview wrapper.
- Modify `ColdHot/Views/SettingsView.swift`: use the new shell and section components, keep all existing bindings/actions, add an internal `initialPage` initializer for deterministic rendering, and configure the real settings window size/titlebar.
- Modify `Scripts/SettingsVisualCheck.swift`: test exact geometry and navigation policy, render every page in dark/light appearance, verify the custom shell replaces `NSSplitView`, and write deterministic PNGs.
- Modify `ColdHot.xcodeproj/project.pbxproj`: add `SettingsChrome.swift` to the Views group and ColdHot Sources phase.
- Modify `Configurations/ReleaseCommon.xcconfig`: increment only `CURRENT_PROJECT_VERSION` from 14 to 15 after all checks pass.

---

### Task 1: Lock Window Geometry and Navigation Contracts

**Files:**
- Create: `ColdHot/Views/SettingsChrome.swift`
- Modify: `Scripts/SettingsVisualCheck.swift`
- Modify: `ColdHot.xcodeproj/project.pbxproj`

**Interfaces:**
- Produces: `SettingsLayout`, `SettingsPage`, and `SettingsSidebarSelection`
- `SettingsLayout.defaultContentSize: CGSize == CGSize(width: 920, height: 720)`
- `SettingsLayout.minimumContentSize: CGSize == CGSize(width: 860, height: 680)`
- `SettingsLayout.sidebarWidth: CGFloat == 204`
- `SettingsSidebarSelection.move(from:direction:) -> SettingsPage`

- [ ] **Step 1: Write failing contract checks**

Move `SettingsPage` out of `SettingsView.swift` only after the test is red. First add these assertions near the beginning of `SettingsVisualCheck.main()`:

```swift
expect(SettingsLayout.defaultContentSize == CGSize(width: 920, height: 720))
expect(SettingsLayout.minimumContentSize == CGSize(width: 860, height: 680))
expect(SettingsLayout.sidebarWidth == 204)
expect(SettingsPage.allCases.map(\.rawValue) == [
    "外观", "指标", "阈值提醒", "通用", "关于"
])
expect(SettingsSidebarSelection.move(from: .appearance, direction: .up) == .about)
expect(SettingsSidebarSelection.move(from: .about, direction: .down) == .appearance)
expect(SettingsSidebarSelection.move(from: .metrics, direction: .down) == .alerts)
```

Add this helper at file scope in the test:

```swift
private func expect(
    _ condition: @autoclosure () -> Bool,
    file: StaticString = #file,
    line: UInt = #line
) {
    guard condition() else {
        fatalError("Check failed", file: file, line: line)
    }
}
```

- [ ] **Step 2: Compile to verify RED**

Run:

```bash
mkdir -p .build/settings-redesign
xcrun swiftc \
  ColdHot/App/BuildVariant.swift \
  ColdHot/Models/MetricKind.swift \
  ColdHot/Models/MonitorSettings.swift \
  ColdHot/Models/PanelBackgroundStore.swift \
  ColdHot/Models/PerformanceSnapshot.swift \
  ColdHot/Models/ThresholdMetric.swift \
  ColdHot/Monitoring/HIDTemperatureReader.swift \
  ColdHot/Monitoring/PerformanceMonitor.swift \
  ColdHot/Monitoring/SMCPowerReader.swift \
  ColdHot/Monitoring/SystemSampler.swift \
  ColdHot/Views/FanSpinnerView.swift \
  ColdHot/Views/MetricRow.swift \
  ColdHot/Views/PanelBackgroundView.swift \
  ColdHot/Views/PanelAppearancePreview.swift \
  ColdHot/Views/PrivacyPolicyView.swift \
  ColdHot/Views/SettingsView.swift \
  Scripts/SettingsVisualCheck.swift \
  -o .build/settings-redesign/SettingsVisualCheck
```

Expected: compilation fails because `SettingsLayout` and `SettingsSidebarSelection` do not exist and `SettingsPage` is private to `SettingsView.swift`.

- [ ] **Step 3: Add the minimal contracts**

Create `SettingsChrome.swift` with:

```swift
import AppKit
import SwiftUI

enum SettingsLayout {
    static let defaultContentSize = CGSize(width: 920, height: 720)
    static let minimumContentSize = CGSize(width: 860, height: 680)
    static let sidebarWidth: CGFloat = 204
    static let pageHorizontalPadding: CGFloat = 34
    static let pageTopPadding: CGFloat = 48
    static let sectionSpacing: CGFloat = 24
    static let rowHeight: CGFloat = 40
}

enum SettingsPage: String, CaseIterable, Identifiable, Hashable {
    case appearance = "外观"
    case metrics = "指标"
    case alerts = "阈值提醒"
    case general = "通用"
    case about = "关于"

    var id: Self { self }

    var slug: String {
        switch self {
        case .appearance: "appearance"
        case .metrics: "metrics"
        case .alerts: "alerts"
        case .general: "general"
        case .about: "about"
        }
    }

    var symbol: String {
        switch self {
        case .appearance: "paintbrush"
        case .metrics: "gauge.with.dots.needle.50percent"
        case .alerts: "exclamationmark.triangle"
        case .general: "gearshape"
        case .about: "info.circle"
        }
    }
}

enum SettingsSidebarMoveDirection { case up, down }

enum SettingsSidebarSelection {
    static func move(
        from current: SettingsPage,
        direction: SettingsSidebarMoveDirection
    ) -> SettingsPage {
        let pages = SettingsPage.allCases
        guard let index = pages.firstIndex(of: current) else { return .appearance }
        switch direction {
        case .up: return pages[(index - 1 + pages.count) % pages.count]
        case .down: return pages[(index + 1) % pages.count]
        }
    }
}
```

Remove the private `SettingsPage` declaration from `SettingsView.swift`. Add the new file to the project Views group and Sources phase.

- [ ] **Step 4: Compile and run to verify GREEN**

Add `ColdHot/Views/SettingsChrome.swift` before `SettingsView.swift` in the Step 2 command. Run the resulting executable with `/tmp/coldhot-settings-baseline.png`.

Expected: assertions pass and the baseline PNG is written.

- [ ] **Step 5: Commit the contracts**

```bash
git add ColdHot/Views/SettingsChrome.swift Scripts/SettingsVisualCheck.swift ColdHot.xcodeproj/project.pbxproj
git add -p ColdHot/Views/SettingsView.swift
git diff --cached --check
git diff --cached
git commit -m "test: define settings redesign contracts"
```

### Task 2: Replace the Default Split View with the A1 Shell

**Files:**
- Modify: `ColdHot/Views/SettingsChrome.swift`
- Modify: `ColdHot/Views/SettingsView.swift`
- Modify: `Scripts/SettingsVisualCheck.swift`

**Interfaces:**
- Consumes: `SettingsLayout`, `SettingsPage`, `SettingsSidebarSelection`
- Produces: `SettingsShell<Content: View>`, `SettingsSidebar`, `LegacySidebarMaterial`, `SettingsSidebarRowStyle`
- `SettingsShell` binds `SettingsPage` and accepts `versionText` plus page content

- [ ] **Step 1: Add failing shell and window assertions**

Change the test window and hosting frame to `SettingsLayout.defaultContentSize`, then replace the current “must contain NSSplitView” assertion with:

```swift
let splitViews = descendants(of: hostingView).compactMap { $0 as? NSSplitView }
expect(splitViews.isEmpty)
expect(window.contentMinSize == SettingsLayout.minimumContentSize)
expect(window.contentLayoutRect.size == SettingsLayout.defaultContentSize)
expect(window.styleMask.contains(.fullSizeContentView))
expect(window.titleVisibility == .hidden)
expect(window.titlebarAppearsTransparent)
expect(window.titlebarSeparatorStyle == .none)
expect(window.toolbar?.isVisible != true)
```

Keep the existing activation-persistence mutation and notification check.

- [ ] **Step 2: Run the visual check to verify RED**

Run the Task 1 compile command and executable.

Expected: it fails because the current view still creates an `NSSplitView`, uses 1040pt minimum width, and does not apply the new content sizes.

- [ ] **Step 3: Implement the custom sidebar and material paths**

Add these behaviors to `SettingsChrome.swift`:

```swift
struct LegacySidebarMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = .sidebar
        nsView.blendingMode = .behindWindow
        nsView.state = .followsWindowActiveState
    }
}
```

Build `SettingsSidebar` as a fixed 204pt `VStack`: a “设置” caption, five plain Buttons at 32pt height, and the existing ColdHot/version footer. Use `@FocusState` and `.onMoveCommand` to call `SettingsSidebarSelection.move`, update both focus and selection, and attach `.accessibilityAddTraits(.isSelected)` only to the current page.

Apply the material with this exact branching policy:

```swift
@ViewBuilder
private var material: some View {
    if reduceTransparency {
        Color(nsColor: .windowBackgroundColor)
    } else if #available(macOS 26.0, *) {
        Color.clear
            .glassEffect(.regular.tint(Color.green.opacity(0.035)), in: Rectangle())
    } else {
        LegacySidebarMaterial()
    }
}
```

The selected row uses `Color.primary.opacity(0.085)` as its neutral background and `Color.green` only for icon/text. Default, hover, pressed, focused, selected, and inactive-window states must remain distinguishable without introducing a blue fill.

Build `SettingsShell` with this interface and structure:

```swift
struct SettingsShell<Content: View>: View {
    @Binding var selection: SettingsPage
    let versionText: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let content: Content

    init(
        selection: Binding<SettingsPage>,
        versionText: String,
        @ViewBuilder content: () -> Content
    ) {
        _selection = selection
        self.versionText = versionText
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(selection: $selection, versionText: versionText)
                .frame(width: SettingsLayout.sidebarWidth)
            ZStack(alignment: .topLeading) {
                content
                    .id(selection)
                    .transition(.opacity)
            }
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.16),
                value: selection
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }
}
```

- [ ] **Step 4: Wire the shell and exact window geometry**

Replace `NavigationSplitView` in `SettingsView.body` with:

```swift
SettingsShell(selection: $selectedPage, versionText: currentVersionText) {
    selectedSettingsPage
}
.frame(
    minWidth: SettingsLayout.minimumContentSize.width,
    idealWidth: SettingsLayout.defaultContentSize.width,
    minHeight: SettingsLayout.minimumContentSize.height,
    idealHeight: SettingsLayout.defaultContentSize.height
)
.background(SettingsWindowConfigurator())
```

In `SettingsWindowConfigurationView`, set `window.contentMinSize` on every idempotent apply. Set `window.setContentSize(SettingsLayout.defaultContentSize)` only the first time a new window instance is configured; do not resize again on activation or later user resizing. Continue to hide the title, transparent titlebar separator, and toolbar after `didBecomeKey` and `didResize`.

- [ ] **Step 5: Run the visual check and inspect the A1 shell**

Compile and run the check. Open the PNG with `view_image`.

Expected: no `NSSplitView`, no centered title, fixed 204pt left navigation, neutral green selected row, traffic lights over the sidebar, and a 920×720 content area.

- [ ] **Step 6: Commit the shell**

```bash
git add ColdHot/Views/SettingsChrome.swift Scripts/SettingsVisualCheck.swift
git add -p ColdHot/Views/SettingsView.swift
git diff --cached --check
git diff --cached
git commit -m "feat: add Apple Music-style settings shell"
```

### Task 3: Replace Grouped Forms with a Consistent Content System

**Files:**
- Modify: `ColdHot/Views/SettingsChrome.swift`
- Modify: `ColdHot/Views/SettingsView.swift`
- Modify: `Scripts/SettingsVisualCheck.swift`

**Interfaces:**
- Consumes: `SettingsPage`, `SettingsLayout`
- Produces: `SettingsPageContent`, `SettingsSectionSurface`, `SettingsRow`, `SettingsSectionDivider`
- Every rendered page exposes `settings-page-<case>` and every section exposes a stable accessibility identifier

- [ ] **Step 1: Add failing five-page accessibility and render checks**

Add an internal initializer to the test call site expectation:

```swift
SettingsView(
    settings: settings,
    panelBackgroundStore: backgroundStore,
    monitor: monitor,
    updateController: UpdateController(),
    initialPage: page
)
```

Loop over `SettingsPage.allCases` and both `NSAppearance.Name.aqua` and `.darkAqua`. For each combination, render a new 920×720 window, require accessibility identifiers `settings-sidebar`, `settings-page-<page-id>`, and at least one `settings-section-<page-id>-0`, then write `<output-directory>/<appearance>-<page>.png`.

Expected initial RED: `SettingsView` has no `initialPage` initializer or stable accessibility identifiers.

- [ ] **Step 2: Add reusable content surfaces**

Implement the components in `SettingsChrome.swift`:

```swift
struct SettingsPageContent<Content: View>: View {
    let page: SettingsPage
    private let content: Content

    init(page: SettingsPage, @ViewBuilder content: () -> Content) {
        self.page = page
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(page.rawValue)
                .font(.system(size: 34, weight: .bold))
                .padding(.bottom, 28)
            ScrollView {
                VStack(alignment: .leading, spacing: SettingsLayout.sectionSpacing) {
                    content
                }
                .frame(maxWidth: 660, alignment: .leading)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.top, SettingsLayout.pageTopPadding)
        .padding(.horizontal, SettingsLayout.pageHorizontalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityIdentifier("settings-page-\(page.slug)")
    }
}
```

`SettingsSectionSurface` renders an optional 13pt semibold title, a rounded 12pt content surface using `Color.primary.opacity(0.045)` in dark mode and `Color.white.opacity(0.64)` in light mode, and an optional caption footer below the surface. `SettingsRow` applies 14pt horizontal padding and `minHeight: 40`. `SettingsSectionDivider` is one pixel at `Color.primary.opacity(0.075)` with 14pt leading inset.

- [ ] **Step 3: Migrate Appearance and About**

Add a custom `SettingsView` initializer that preserves existing defaults and sets `_selectedPage = State(initialValue: initialPage)`.

Replace the two grouped Forms with `SettingsPageContent` and explicit `SettingsSectionSurface` blocks. Preserve exact controls and actions. Put every `LabeledContent`, Button, Toggle, slider group, capability row, and runtime value in `SettingsRow`; insert `SettingsSectionDivider` between peer rows. Use identifiers `settings-section-appearance-0`, `settings-section-appearance-1` when readability warning is present, `settings-section-about-0`, `settings-section-about-1`, and `settings-section-about-2`.

- [ ] **Step 4: Migrate Metrics, Alerts, and General**

Replace their Forms with the same components and keep all DisclosureGroup bindings and controls unchanged. Use identifiers:

```text
settings-section-metrics-0       quick presets
settings-section-metrics-1       enabled metric groups
settings-section-alerts-0        notification controls
settings-section-alerts-1        threshold groups
settings-section-general-0       updates, direct builds only
settings-section-general-1       Dock shortcut, supported builds only
settings-section-general-2       sampling
settings-section-general-3       build summary/reset
```

For conditionally absent sections, the test checks the first available identifier and page identifier rather than requiring unavailable build-variant content.

- [ ] **Step 5: Run all ten page renders and inspect them**

Run the visual executable with `/tmp/coldhot-settings-a1` as its output directory, then inspect all PNGs as a contact sheet or individually.

Expected: five pages × two appearances, consistent 34pt title, 24pt section rhythm, 40pt row baseline, no default grouped Form chrome, no horizontal clipping, and no meaningless scrollbar on short pages.

- [ ] **Step 6: Commit the content system**

```bash
git add ColdHot/Views/SettingsChrome.swift Scripts/SettingsVisualCheck.swift
git add -p ColdHot/Views/SettingsView.swift
git diff --cached --check
git diff --cached
git commit -m "feat: unify settings content surfaces"
```

### Task 4: Preserve the True Panel Preview in the Compact Window

**Files:**
- Modify: `ColdHot/Views/SettingsChrome.swift`
- Modify: `ColdHot/Views/SettingsView.swift`
- Modify: `Scripts/SettingsVisualCheck.swift`

**Interfaces:**
- Produces: `SettingsPreviewScale.factor(contentWidth:availableWidth:) -> CGFloat`
- Produces: `ScaledSettingsPreview<Content: View>` that changes presentation size without changing the content's logical layout

- [ ] **Step 1: Add failing scale policy checks**

Add:

```swift
expect(SettingsPreviewScale.factor(contentWidth: 370, availableWidth: 370) == 1)
expect(abs(SettingsPreviewScale.factor(contentWidth: 370, availableWidth: 296) - 0.8) < 0.0001)
expect(SettingsPreviewScale.factor(contentWidth: 370, availableWidth: 500) == 1)
```

Expected RED: `SettingsPreviewScale` does not exist.

- [ ] **Step 2: Implement measured scaling without crop changes**

Add:

```swift
enum SettingsPreviewScale {
    static func factor(contentWidth: CGFloat, availableWidth: CGFloat) -> CGFloat {
        guard contentWidth > 0 else { return 1 }
        return min(1, max(0, availableWidth / contentWidth))
    }
}
```

Implement `ScaledSettingsPreview` with a `PreferenceKey` that measures the fixed-size logical content, applies `.scaleEffect(scale, anchor: .topLeading)`, and then supplies the scaled width and height to its outer frame. Do not pass a smaller width into `PanelAppearancePreview`; its internal `.frame(width: PanelLayout.width)` remains 370.

- [ ] **Step 3: Recompose the Appearance page**

Inside `SettingsPageContent`, give the settings column the flexible leading area and the preview a maximum presented width of 320pt at 920px and 296pt at 860px. Use a 24pt inter-column gap. Keep the existing “菜单面板真实范围” heading and explanatory text. Apply the existing rounded clipping and border outside `ScaledSettingsPreview` so the border follows the scaled bounds.

- [ ] **Step 4: Render default and minimum widths**

Extend the visual check to render the Appearance page at 920×720 and 860×680 in both appearances. Verify the accessibility label “菜单面板外观预览” remains present.

Expected: preview shows the exact same image crop and seven-card viewport at both sizes, scaled to fit with no horizontal crop or altered menu data.

- [ ] **Step 5: Commit preview scaling**

```bash
git add ColdHot/Views/SettingsChrome.swift Scripts/SettingsVisualCheck.swift
git add -p ColdHot/Views/SettingsView.swift
git diff --cached --check
git diff --cached
git commit -m "fix: scale the true panel preview in settings"
```

### Task 5: Full Verification, Local Build 15, and Installation

**Files:**
- Modify: `Configurations/ReleaseCommon.xcconfig`
- Verify: all modified source and script files
- Generate: `dist/local-test/1.3.0-15/ColdHot-Direct-1.3.0-15-local-test.dmg`

**Interfaces:**
- Consumes: completed A1 settings implementation
- Produces: locally signed build 15 installed at `/Applications/ColdHot.app`

- [ ] **Step 1: Run source-level accounting and ownership checks**

```bash
mkdir -p .build/settings-redesign
xcrun swiftc \
  ColdHot/App/BuildVariant.swift \
  ColdHot/Models/MetricKind.swift \
  ColdHot/Models/ThresholdMetric.swift \
  ColdHot/Models/PerformanceSnapshot.swift \
  ColdHot/Monitoring/HIDTemperatureReader.swift \
  ColdHot/Monitoring/SMCPowerReader.swift \
  ColdHot/Monitoring/SystemSampler.swift \
  Scripts/ProcessCPUAccountingCheck.swift \
  -o .build/settings-redesign/ProcessCPUAccountingCheck
.build/settings-redesign/ProcessCPUAccountingCheck
xcrun swiftc \
  ColdHot/App/BuildVariant.swift \
  ColdHot/Models/MetricKind.swift \
  ColdHot/Models/ThresholdMetric.swift \
  ColdHot/Models/PerformanceSnapshot.swift \
  ColdHot/Monitoring/HIDTemperatureReader.swift \
  ColdHot/Monitoring/SMCPowerReader.swift \
  ColdHot/Monitoring/SystemSampler.swift \
  Scripts/MemoryAccountingCheck.swift \
  -o .build/settings-redesign/MemoryAccountingCheck
.build/settings-redesign/MemoryAccountingCheck
xcrun swiftc -parse-as-library Scripts/HIDTemperatureOwnershipCheck.swift -o .build/settings-redesign/HIDTemperatureOwnershipCheck
.build/settings-redesign/HIDTemperatureOwnershipCheck
```

Expected: CPU, memory, and HID ownership checks pass.

- [ ] **Step 2: Run UI and behavior checks**

Compile and run the Task 1 settings command, then run:

```bash
xcrun swiftc \
  ColdHot/App/BuildVariant.swift \
  ColdHot/Models/MetricKind.swift \
  ColdHot/Models/MonitorSettings.swift \
  ColdHot/Models/PerformanceSnapshot.swift \
  ColdHot/Models/ThresholdMetric.swift \
  Scripts/ThresholdLogicCheck.swift \
  -o .build/settings-redesign/ThresholdLogicCheck
.build/settings-redesign/ThresholdLogicCheck

xcrun swiftc \
  ColdHot/Views/PanelBackgroundView.swift \
  Scripts/PanelLayoutBehaviorCheck.swift \
  -o .build/settings-redesign/PanelLayoutBehaviorCheck
.build/settings-redesign/PanelLayoutBehaviorCheck

xcrun swiftc \
  ColdHot/Views/FanSpinnerView.swift \
  Scripts/FanSpinnerCenterCheck.swift \
  -o .build/settings-redesign/FanSpinnerCenterCheck
.build/settings-redesign/FanSpinnerCenterCheck /tmp/coldhot-fan-center-build15.png

xcrun swiftc \
  ColdHot/App/BuildVariant.swift \
  ColdHot/Models/MetricKind.swift \
  ColdHot/Models/MonitorSettings.swift \
  ColdHot/Models/PanelBackgroundStore.swift \
  ColdHot/Models/PerformanceSnapshot.swift \
  ColdHot/Models/ThresholdMetric.swift \
  ColdHot/Views/FanSpinnerView.swift \
  ColdHot/Views/MetricRow.swift \
  ColdHot/Views/PanelBackgroundView.swift \
  ColdHot/Views/PanelAppearancePreview.swift \
  Scripts/PanelBackgroundCheck.swift \
  -o .build/settings-redesign/PanelBackgroundCheck
.build/settings-redesign/PanelBackgroundCheck

xcrun swiftc \
  ColdHot/App/BuildVariant.swift \
  ColdHot/Models/MetricKind.swift \
  ColdHot/Models/MonitorSettings.swift \
  ColdHot/Models/PerformanceSnapshot.swift \
  ColdHot/Models/ThresholdMetric.swift \
  ColdHot/Monitoring/HIDTemperatureReader.swift \
  ColdHot/Monitoring/PerformanceMonitor.swift \
  ColdHot/Monitoring/SMCPowerReader.swift \
  ColdHot/Monitoring/SystemSampler.swift \
  Scripts/PerformanceMonitorRuntimeCheck.swift \
  -o .build/settings-redesign/PerformanceMonitorRuntimeCheck
.build/settings-redesign/PerformanceMonitorRuntimeCheck
```

Record every command and result in the handoff; no check may be skipped silently.

Expected: all checks pass; the settings check emits dark/light screenshots for all pages and minimum-size Appearance screenshots.

- [ ] **Step 3: Build the Direct target without signing**

```bash
xcodebuild -project ColdHot.xcodeproj \
  -scheme "ColdHot Direct" \
  -configuration DirectRelease \
  -destination "generic/platform=macOS" \
  -derivedDataPath .build/settings-redesign/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  clean build
```

Expected: `** BUILD SUCCEEDED **` with deployment target 14.0.

- [ ] **Step 4: Run real Settings Scene visual checks**

Launch the built app, open Settings through the menu panel, and capture the real window rather than only the harness. Check:

```text
content size 920×720 on first open
minimum resize stops at 860×680
no centered “ColdHot Settings” title
traffic lights remain aligned over the sidebar
selected row is neutral + green, never system blue
sidebar is fixed while long detail pages scroll
About has no unnecessary scrollbar
all five pages keep one window size
Reduce Transparency produces an opaque sidebar
Reduce Motion removes the page fade
closing and reopening Settings preserves titlebar configuration
```

If any item fails, add a regression assertion before changing production code.

- [ ] **Step 5: Increment to build 15 only after GREEN**

Change:

```xcconfig
CURRENT_PROJECT_VERSION = 15
```

Run the clean Direct build again and verify `CFBundleShortVersionString = 1.3.0` and `CFBundleVersion = 15` in the built app.

- [ ] **Step 6: Create the local-test DMG**

```bash
./Scripts/build-releases.sh local-test
coldhot_verify_mount="$(mktemp -d /tmp/coldhot-build15-verify.XXXXXX)"
hdiutil attach -nobrowse \
  -mountpoint "$coldhot_verify_mount" \
  dist/local-test/1.3.0-15/ColdHot-Direct-1.3.0-15-local-test.dmg
codesign --verify --deep --strict "$coldhot_verify_mount/ColdHot.app"
hdiutil detach "$coldhot_verify_mount"
rmdir "$coldhot_verify_mount"
```

Expected: the script creates the DMG and SHA256 file, and the mounted `ColdHot.app` passes strict code-signature verification.

- [ ] **Step 7: Back up and install safely**

Resolve the exact source app by mounting the DMG. Quit only the running ColdHot process, move the existing `/Applications/ColdHot.app` to a uniquely named path in `~/.Trash`, copy the verified new app into `/Applications`, eject the DMG, and launch ColdHot. Do not delete the backup.

- [ ] **Step 8: Verify installed runtime and request visual confirmation**

Open the installed Settings window and repeat the real Settings Scene checklist. Sample the running process for CPU, resident memory, and wakeups long enough to catch idle regressions. Report the installed version, backup location, DMG path, screenshot paths, test outcomes, and remaining visual risks.

- [ ] **Step 9: Commit the verified build metadata and final source**

```bash
git add Configurations/ReleaseCommon.xcconfig ColdHot/Views/SettingsChrome.swift Scripts/SettingsVisualCheck.swift ColdHot.xcodeproj/project.pbxproj
git add -p ColdHot/Views/SettingsView.swift
git diff --cached --check
git diff --cached
git commit -m "feat: finish Apple Music-style settings redesign"
```
