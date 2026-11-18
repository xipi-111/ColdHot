# English Localization Implementation Plan

> **For agentic workers:** Use superpowers:subagent-driven-development or superpowers:executing-plans to implement the work. Steps use checkbox syntax for tracking.

**Goal:** Add a complete English interface alongside Simplified Chinese.

**Architecture:** Native Foundation bundle localization with English fallback. Localize strings at their origin so SwiftUI, AppKit, notifications, and accessibility share translations. Preserve raw enum identities and local preferences.

**Tech Stack:** Swift, SwiftUI, Foundation, Xcode, localized strings resources.

**Spec:** `docs/superpowers/specs/2026-11-18-english-localization-design.md`

## Global Constraints

- macOS 14 minimum, no additional dependencies.
- Keep existing enum identities and preference keys unchanged.
- No Figma access. Release follow-up authorized: publish the Direct version 1.6.0 (28) through the existing signed update feed.

## Review Focus

- English strings flow through custom views accepting `String`.
- Interpolated notifications, measurements, and accessibility descriptions retain argument order.
- Chinese users retain complete Chinese labels and existing settings.
- English labels fit compact cards and settings rows.
- Both language resources are included in the actual app bundle.

### Task 1: Establish bundle localization and validation

- [x] Add a focused check of language resources, placeholder parity, and actual bundle lookup; confirm missing resources fail before implementation.
- [x] Register English and Simplified Chinese Localizable.strings resources in the Xcode project.

### Task 2: Localize all app surfaces

- [x] Convert dashboard, settings, preview, privacy, accessibility, errors, and model display strings to native localized lookups.
- [x] Use localized display properties instead of changing enum raw values.
- [x] Populate complete matching English and Chinese dictionaries.

### Task 3: Verify and review

- [x] Build the Direct scheme and verify bundled translations, fallback, and format arguments.
- [x] Run threshold regression checks and render representative English UI.
- [x] Review translation coverage and code diff independently; resolve material findings.

## Verification evidence

- DirectRelease build succeeded with both localized resource tables embedded.
- `swift Scripts/LocalizationCheck.swift .build/english-localization/Build/Products/DirectRelease/ColdHot.app` passed for all 371 messages.
- `ThresholdLogicCheck` passed with the current models.
- An isolated visual harness rendered all five settings pages at 860 × 680, the privacy view, and the 370 px panel in English and Simplified Chinese.
- Independent review found only a plural-count wording issue; sensor and cycle values now display the number beside their existing labels.
- Shortened the background format summary for the narrow appearance row and added English status punctuation after visual inspection.

## Release follow-up

- [x] Set version 1.6.0 / build 28 and add bilingual release notes.
- [x] Archive and export a universal Developer ID signed app.
- [x] Obtain Apple notarization acceptance and staple the DMG.
- [x] Verify app signature, Gatekeeper acceptance, architectures, and all 371 translations from the final DMG.
- [x] Verify the generated Sparkle signature against the installed app’s public key.
- [x] Publish GitHub release assets and verify the downloadable bytes.
- [x] Push the production appcast and verify update discovery from the installed app.

## Release verification results

- Published: https://github.com/xipi-111/ColdHot/releases/tag/v1.6.0
- Source tag: `v1.6.0`, commit `9edd963`. Signed update feed: commit `39ceca4`.
- Apple notarization accepted submission `00dfbe5c-f354-49da-ac44-c9397766b51f`; DMG ticket stapled and Gatekeeper accepted the app and DMG.
- Final DMG contains both x86_64 and arm64 executables and all 371 English / Simplified Chinese messages.
- Sparkle Ed25519 signature verified against the key embedded in the currently installed app. Anonymous downloads of the public DMG and checksums match the local release bytes.
- Production feed returned 1.6.0 / build 28 and matched the signed appcast byte for byte.
- A read-only Sparkle information check targeting the installed ColdHot 1.5.2 (27) found ColdHot 1.6.0 (28) and the correct public DMG URL.
