# Native Settings and Panel Motion Spec

## Goal

Make the settings window visually consistent with the macOS 26 Apple Music sidebar, make card disclosure motion smooth without changing settled card visuals, and keep threshold alerts out of the opened panel.

## Confirmed behavior

- Settings uses the native macOS sidebar/navigation container. On macOS 26 the system supplies the floating Liquid Glass treatment; older supported systems use their native fallback.
- Existing settings pages, controls, preview, window focus behavior, and green ColdHot accent remain available.
- Card expansion preserves the current collapsed and fully expanded static appearance.
- Expansion positioning and geometry changes do not animate simultaneously. Details fade in during the geometry transition; collapse reverses the sequence. Rapid taps cancel stale phases and Reduce Motion is respected.
- Threshold evaluation, compact menu-bar alert values, and optional system notifications remain. Opening the panel does not show a threshold banner, add disabled alert metrics, automatically expand a card, or automatically scroll because of an alert.
- With every card collapsed, the metrics area cannot scroll or bounce. Its content has no scroll-only trailing space. Scrolling is enabled only while a card is expanded, and its indicator remains hidden.

## Acceptance checks

- A rendered settings window contains a native split-view/sidebar hierarchy and retains the transparent title bar after activation.
- A collapsed seven-card panel has document height no greater than its viewport and ignores scroll input.
- An expanded panel can scroll without a visible vertical scroller.
- Panel metric visibility is derived only from the user-enabled metric set.
- Expansion phase tests prove positioning ends before geometry begins, details appear during expansion, collapse fades details before geometry, stale phases are cancellable, and Reduce Motion removes animation delays.
- Clean Direct build and the existing monitoring regression scripts pass.

