# English localization

Add an English version of ColdHot while retaining Simplified Chinese. Use native bundle localization so the app follows the user's preferred language and macOS can set its language independently. The implementation uses native system language selection as the default.

Cover the dashboard, settings, preview, privacy policy, notifications, errors, and accessibility descriptions. Keep metrics, sampling, persisted settings, and enum identities unchanged. Keep the existing Direct distribution. Publication was outside the initial implementation scope; the user subsequently authorized a signed, notarized release so the installed app can update itself.

Use Foundation `String(localized:)` and matching `en.lproj` / `zh-Hans.lproj` resources. Format dynamic sentences as complete localizable messages. English is the fallback language. An in-app language preference would add persistence and refresh/restart behavior; macOS already supplies per-app language selection, so native selection is the smaller complete implementation.

Verify resource parity and format placeholders, build the Direct scheme, run targeted existing checks, and render representative English settings/dashboard content to check longer labels.

## Authorized release follow-up

Publish version 1.6.0, build 28. The build number must exceed the installed development version 1.5.2 (27), as well as the public version 1.5.1 (25). Preserve the bundle identifier, update feed URL, and existing Sparkle public key. Verify the universal signed and notarized DMG, then publish its assets before exposing the new appcast on main.
