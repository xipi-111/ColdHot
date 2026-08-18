# ColdHot Icon And Readability Preview Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the application icon and make primary text, secondary text, and progress opacity independently adjustable with a live settings preview.

**Architecture:** Extend `MonitorSettings` with migrated role-specific opacity values, expose them through role-aware SwiftUI environment modifiers, and make both the dashboard and a deterministic preview consume the same modifiers. Keep icon generation separate as a source artwork plus the existing macOS asset-size generator.

**Tech Stack:** Swift 5, SwiftUI, AppKit, UserDefaults, Xcode asset catalogs, standalone Swift regression checks.

**Spec:** `docs/superpowers/specs/2026-08-18-icon-readability-preview-design.md`

## Global Constraints

- Direct-distribution macOS app; do not add third-party dependencies.
- Custom-background controls affect the panel only when a stored image is enabled.
- Preserve existing users' visual appearance by migrating legacy `panelTextOpacity` into both new text roles.
- The settings preview uses deterministic sample content, starts no performance sampling, and uses the dashboard's actual 370px panel width and collapsed-height rules.
- Keep the icon legible from 16px through 1024px.

---

### Task 1: Persist migrated readability controls

**Files:**
- Modify: `ColdHot/Models/MonitorSettings.swift`
- Modify: `Scripts/PanelBackgroundCheck.swift`

**Interfaces:**
- Produces: `panelPrimaryTextOpacity`, `panelSecondaryTextOpacity`, `panelProgressOpacity`.
- Produces: `setPanelPrimaryTextOpacity(_:)`, `setPanelSecondaryTextOpacity(_:)`, `setPanelProgressOpacity(_:)`.

- [ ] **Step 1: Write failing persistence and migration checks**

Add assertions for independent persistence, 0.50...1 clamping, reset behavior, and migration from a legacy `panelTextOpacity` value into both text roles while progress defaults to 1.

- [ ] **Step 2: Run the panel check and verify RED**

Run the existing standalone Swift compile command and confirm it fails because the new settings APIs do not exist.

- [ ] **Step 3: Implement the minimal settings model**

Add three published values, setters, keys, legacy lookup, and reset calls. Preserve the old key only as a migration input.

- [ ] **Step 4: Run the panel check and verify GREEN**

Recompile and run `.build/icon-readability-preview/PanelBackgroundCheck`; expect `Panel background checks passed`.

### Task 2: Add role-aware panel rendering

**Files:**
- Modify: `ColdHot/Views/PanelBackgroundView.swift`
- Modify: `ColdHot/Views/MetricRow.swift`
- Modify: `ColdHot/Views/DashboardView.swift`
- Modify: `Scripts/PanelBackgroundCheck.swift`

**Interfaces:**
- Produces: `PanelTextRole.primary`, `PanelTextRole.secondary`.
- Produces: `panelTextReadability(_:)` and `panelProgressReadability()`.
- Changes: `panelReadability(cardOpacity:primaryTextOpacity:secondaryTextOpacity:progressOpacity:usesCustomBackground:)`.

- [ ] **Step 1: Write failing independent render checks**

Render white test blocks using each role over black. Assert dimming primary does not dim secondary, dimming secondary does not dim primary, progress changes independently, and all remain native when custom background is disabled.

- [ ] **Step 2: Compile and verify RED**

Confirm compilation fails because the role and progress modifiers do not exist.

- [ ] **Step 3: Implement environment values and modifiers**

Inject the three values and clamp each to 0.50...1 only while custom background is active. Keep the existing readability shadow for both text roles.

- [ ] **Step 4: Classify every dashboard label**

Apply primary to titles/current values/detail section titles/detail values and secondary to timestamps/descriptions/labels/status/PID/footer. Apply progress readability to determinate metric progress bars.

- [ ] **Step 5: Run the render check and verify GREEN**

Recompile and run the check, then mutation-check each role by swapping one environment key and confirming the corresponding assertion would fail.

### Task 3: Add the live settings preview

**Files:**
- Create: `ColdHot/Views/PanelAppearancePreview.swift`
- Modify: `ColdHot/Views/SettingsView.swift`
- Modify: `ColdHot.xcodeproj/project.pbxproj`
- Modify: `Scripts/PanelBackgroundCheck.swift`

**Interfaces:**
- Produces: `PanelAppearancePreview`, consuming an optional `NSImage`, current metric/Dock configuration, and all five appearance values.

- [ ] **Step 1: Add a failing preview render check**

Render the preview with a controlled split-color image and assert it produces a non-empty 370px-wide bitmap whose height follows the collapsed dashboard rules. Verify the sampled top/bottom crop matches a production `PanelBackgroundView` rendered at the same exact bounds, then verify card/text/progress areas react to opacity changes.

- [ ] **Step 2: Compile and verify RED**

Confirm compilation fails because `PanelAppearancePreview` is missing.

- [ ] **Step 3: Implement a deterministic production-style preview**

Build a 370px-wide panel with production-equivalent header, enabled metric cards, optional Dock area, footer, primary/secondary labels, and progress bars using `PanelBackgroundView`, `PanelCardBackground`, and the production readability modifiers. Derive the collapsed canvas height from the same layout constants as the real dashboard.

- [ ] **Step 4: Replace the thumbnail and split the controls**

Show the true-aspect panel preview above the background controls, add three bindings/sliders, and retain choose/replace/remove actions. Display the 370px canvas at native width when space allows; if scaled, preserve its exact aspect ratio and crop.

- [ ] **Step 5: Verify preview and app build GREEN**

Run the panel check and a Debug `ColdHot Direct` build with signing disabled.

### Task 4: Replace and validate the app icon

**Files:**
- Replace: `Artwork/ColdHot-AppIcon-Fan-Source.png`
- Modify: `Scripts/generate-app-icons.swift`
- Replace: `ColdHot/Resources/Assets.xcassets/AppIcon.appiconset/*.png`

**Interfaces:**
- Consumes: approved light-background, dark hand-drawn pulse artwork.
- Produces: ten macOS app-icon PNG assets declared in `Contents.json`.

- [ ] **Step 1: Generate the approved source artwork**

Use the provided photo only as a shape/style reference. Generate a centered minimal pulse symbol with no photo background, text, fan, gauge, glow, or excessive detail.

- [ ] **Step 2: Inspect and normalize the 1024px source**

Confirm the safe margin, color contrast, square dimensions, and legibility at 16px and 32px.

- [ ] **Step 3: Generate the asset catalog sizes**

Run `Scripts/generate-app-icons.swift` into `AppIcon.appiconset` and update its success message/default source naming if needed.

- [ ] **Step 4: Validate every declared icon asset**

Read `Contents.json`, confirm all ten files exist with exact expected pixel dimensions, and render a contact sheet for visual inspection.

### Task 5: Full verification and handoff

**Files:**
- Review all changed files.

**Interfaces:**
- Produces: a buildable Direct-distribution change set ready for release packaging after user approval.

- [ ] **Step 1: Run all six standalone regression checks**

Freshly compile and run Threshold, fan center, panel background, process CPU, memory accounting, and HID ownership checks.

- [ ] **Step 2: Run Direct analysis and build**

Run `xcodebuild` for `ColdHot Direct` in `DirectRelease` with signing disabled, including `analyze` and `build`.

- [ ] **Step 3: Review scope and repository state**

Inspect `git diff --check`, changed-file list, versioned icon sizes, and verify no generated build products are staged.

- [ ] **Step 4: Present the user-visible result**

Show the icon and preview capture, summarize controls and migration, and ask before publishing a new release.
