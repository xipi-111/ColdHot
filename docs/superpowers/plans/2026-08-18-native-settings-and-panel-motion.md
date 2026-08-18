# Native Settings and Panel Motion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver a native macOS 26 settings sidebar, smoother interruptible card motion, normal panel opening during threshold alerts, and a non-scrollable compact collapsed panel.

**Architecture:** Replace the custom settings shell with `NavigationSplitView` while leaving page content intact. Put panel visibility, scrolling, and motion sequencing behind small pure policies in `PanelBackgroundView.swift`, exercise them from executable regression checks, and let `DashboardView` apply those policies without global SwiftUI animation transactions.

**Tech Stack:** Swift 5, SwiftUI, AppKit, macOS 14 deployment target with macOS 26 native appearance.

**Spec:** `docs/superpowers/specs/2026-08-18-native-settings-and-panel-motion.md`

## Global Constraints

- Preserve existing collapsed and fully expanded card visual styling.
- Keep threshold evaluation, menu-bar alert values, and optional system notifications.
- Do not add dependencies or unrelated refactors.
- Preserve all existing uncommitted user work.

---

### Task 1: Lock panel behavior with failing checks

**Files:**
- Modify: `Scripts/PanelLayoutBehaviorCheck.swift`
- Modify: `Scripts/PanelBackgroundCheck.swift`
- Modify: `ColdHot/Views/PanelBackgroundView.swift`

**Interfaces:**
- Consumes: `PanelLayout.metricsViewportHeight`, `PanelExpansionBehavior`, `PanelExpansionAnimationPlan`
- Produces: `PanelMetricVisibility.visibleMetrics`, `PanelScrollBehavior.isScrollEnabled`, revised transition phase values

- [ ] **Step 1: Write failing behavior checks**

Add literal expectations proving that an active alert cannot inject a disabled metric, the collapsed state disables scrolling, and positioning completes before expansion geometry begins while details fade in before geometry completes.

- [ ] **Step 2: Run the focused checks and verify RED**

Run the same `swiftc` command used by the existing panel layout check and the panel rendering check. Expected: compilation or assertion failure because the new policies and phase ordering do not exist.

- [ ] **Step 3: Implement the minimum pure policies**

Add small value-type policies that return visible metrics from user settings only, enable scrolling only for an expanded metric, and return non-overlapping positioning/layout/detail phases with zero-delay Reduce Motion values.

- [ ] **Step 4: Run the focused checks and verify GREEN**

Expected: both executable checks print their success messages without warnings or crashes.

### Task 2: Apply the panel policies

**Files:**
- Modify: `ColdHot/Views/DashboardView.swift`
- Modify: `ColdHot/Views/MetricRow.swift`

**Interfaces:**
- Consumes: the policies from Task 1
- Produces: user-only cards, no in-panel alert presentation, scoped geometry animation, collapsed scroll lock

- [ ] **Step 1: Remove alert-only panel presentation**

Delete the alert banner, alert-driven `onAppear`/`onChange` reveal path, and alert metric union. Keep the monitor alert state untouched for the status item and notifications.

- [ ] **Step 2: Replace lazy card layout and lock collapsed scrolling**

Use `VStack` for the maximum seven cards, set `.scrollDisabled` from `PanelScrollBehavior`, and remove scroll-only content redundancy while retaining 12-point card insets.

- [ ] **Step 3: Scope and sequence motion**

Run scroll positioning and expansion geometry in separate phases, attach geometry animation only to card expansion state, fade expanded details according to the plan, and use the transition generation to discard stale delayed work.

- [ ] **Step 4: Re-run panel checks**

Expected: layout, background, and threshold checks all pass.

### Task 3: Adopt the native settings sidebar

**Files:**
- Modify: `Scripts/SettingsVisualCheck.swift`
- Modify: `ColdHot/Views/SettingsView.swift`

**Interfaces:**
- Consumes: existing `SettingsPage` selection and page views
- Produces: a `NavigationSplitView` with a native sidebar `List`

- [ ] **Step 1: Add a failing native hierarchy check**

Render the real settings view and require an AppKit split-view hierarchy with a sidebar list, while retaining the persistent transparent-titlebar assertions.

- [ ] **Step 2: Run the visual check and verify RED**

Expected: hierarchy assertion fails against the custom `HStack` implementation.

- [ ] **Step 3: Implement the native shell**

Replace the custom sidebar buttons/divider with `NavigationSplitView` and a selection-bound `.sidebar` list. Keep version information in a bottom safe-area inset and keep page headings/content unchanged.

- [ ] **Step 4: Run the visual check and inspect its PNG**

Expected: native floating sidebar on macOS 26, correctly placed traffic lights, complete labels, and unchanged detail-page content.

### Task 4: Full verification and installation

**Files:**
- Modify: `ColdHot.xcodeproj/project.pbxproj`
- Modify: `Configurations/ReleaseCommon.xcconfig`

**Interfaces:**
- Consumes: completed UI behavior
- Produces: the next local-test build and installed application

- [ ] **Step 1: Run all project regression scripts and a clean Direct build**

Expected: fan, HID ownership, memory accounting, CPU accounting, threshold, runtime, panel layout, panel background, settings visual, codesign, and clean Direct build all pass.

- [ ] **Step 2: Compare settled screenshots and sample interactions**

Capture collapsed and expanded panel states plus the settings window. Confirm settled card geometry is unchanged, no collapsed scrollbar appears, alerts do not alter panel opening, and repeated disclosure interactions do not show main-thread layout bursts.

- [ ] **Step 3: Increment the build, create a local-test DMG, and install safely**

Back up the existing `/Applications/ColdHot.app` to a unique Trash path, install the verified build, launch it, and repeat the installed-app smoke checks.

