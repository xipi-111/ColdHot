import SwiftUI

@main
enum PanelLayoutBehaviorCheck {
    static func main() {
        checkCollapsedHeightRange()
        checkExpandedHeightLimit()
        checkPanelMetricVisibility()
        checkPanelScrollBehavior()
        checkExpansionDecision()
        checkExpansionAnimationOrder()
        checkProgrammaticPresentation()
        print("Panel layout behavior checks passed")
    }

    private static func checkCollapsedHeightRange() {
        expect(PanelLayout.metricsViewportHeight(metricCount: 1, hasExpandedMetric: false) == 296)
        expect(PanelLayout.metricsViewportHeight(metricCount: 3, hasExpandedMetric: false) == 296)
        expect(PanelLayout.metricsViewportHeight(metricCount: 4, hasExpandedMetric: false) == 296)
        expect(PanelLayout.metricsViewportHeight(metricCount: 5, hasExpandedMetric: false) == 366)
        expect(PanelLayout.metricsViewportHeight(metricCount: 6, hasExpandedMetric: false) == 436)
        expect(PanelLayout.metricsViewportHeight(metricCount: 7, hasExpandedMetric: false) == 512)
        expect(PanelLayout.metricsViewportHeight(metricCount: 10, hasExpandedMetric: false) == 512)
    }

    private static func checkExpandedHeightLimit() {
        expect(PanelLayout.metricsViewportHeight(metricCount: 1, hasExpandedMetric: true) == 512)
        expect(PanelLayout.metricsViewportHeight(metricCount: 4, hasExpandedMetric: true) == 512)
        expect(PanelLayout.metricsViewportHeight(metricCount: 7, hasExpandedMetric: true) == 512)
    }

    private static func checkPanelMetricVisibility() {
        let visible = PanelMetricVisibility.visibleMetrics(
            available: ["cpu", "gpu", "battery"],
            userEnabled: Set(["cpu", "gpu"]),
            activeAlertMetrics: Set(["battery"])
        )
        expect(visible == ["cpu", "gpu"])
    }

    private static func checkPanelScrollBehavior() {
        expect(!PanelScrollBehavior.allowsScrolling(expandedMetric: Optional<String>.none))
        expect(PanelScrollBehavior.allowsScrolling(expandedMetric: "cpu"))
    }

    private static func checkExpansionDecision() {
        let firstExpansion = PanelExpansionBehavior.decision(
            toggling: "cpu",
            current: nil
        )
        expect(firstExpansion.expandedMetric == "cpu")
        expect(firstExpansion.scrollTarget == "cpu")

        let collapse = PanelExpansionBehavior.decision(
            toggling: "cpu",
            current: "cpu"
        )
        expect(collapse.expandedMetric == nil)
        expect(collapse.scrollTarget == nil)

        let switchExpansion = PanelExpansionBehavior.decision(
            toggling: "memory",
            current: "cpu"
        )
        expect(switchExpansion.expandedMetric == "memory")
        expect(switchExpansion.scrollTarget == "memory")
    }

    private static func checkExpansionAnimationOrder() {
        let expansion = PanelExpansionAnimationPlan.transition(
            from: Optional<String>.none,
            to: "cpu",
            reduceMotion: false
        )
        expect(expansion.initialVisibleDetails == nil)
        expect(expansion.layoutMetric == "cpu")
        expect(expansion.layoutDelay == 0)
        expect(expansion.finalVisibleDetails == "cpu")
        expect(expansion.detailsDelay > expansion.layoutDelay)
        expect(expansion.initialDetailsAnimationDuration == 0)
        expect(expansion.finalDetailsAnimationDuration > 0)
        expect(expansion.scrollTarget == "cpu")
        expect(expansion.scrollDelay >= expansion.layoutDelay + expansion.layoutAnimationDuration)
        expect(expansion.scrollAnimationDuration > 0)

        let collapse = PanelExpansionAnimationPlan.transition(
            from: "cpu",
            to: Optional<String>.none,
            reduceMotion: false
        )
        expect(collapse.initialVisibleDetails == nil)
        expect(collapse.layoutMetric == nil)
        expect(collapse.layoutDelay > 0)
        expect(collapse.initialDetailsAnimationDuration > 0)
        expect(collapse.layoutDelay >= collapse.initialDetailsAnimationDuration)
        expect(collapse.finalVisibleDetails == nil)
        expect(collapse.scrollTarget == nil)
        expect(collapse.scrollAnimationDuration == 0)

        let switchMetric = PanelExpansionAnimationPlan.transition(
            from: "cpu",
            to: "memory",
            reduceMotion: false
        )
        expect(switchMetric.initialVisibleDetails == nil)
        expect(switchMetric.layoutMetric == "memory")
        expect(switchMetric.layoutDelay > 0)
        expect(switchMetric.finalVisibleDetails == "memory")
        expect(switchMetric.detailsDelay > switchMetric.layoutDelay)
        expect(switchMetric.initialDetailsAnimationDuration > 0)
        expect(switchMetric.finalDetailsAnimationDuration > 0)
        expect(switchMetric.scrollTarget == "memory")
        expect(switchMetric.scrollDelay >= switchMetric.layoutDelay + switchMetric.layoutAnimationDuration)
        expect(switchMetric.scrollAnimationDuration > 0)

        let reducedMotion = PanelExpansionAnimationPlan.transition(
            from: "cpu",
            to: "memory",
            reduceMotion: true
        )
        expect(reducedMotion.layoutDelay == 0)
        expect(reducedMotion.detailsDelay == 0)
        expect(reducedMotion.initialDetailsAnimationDuration == 0)
        expect(reducedMotion.finalDetailsAnimationDuration == 0)
        expect(reducedMotion.scrollDelay == 0)
        expect(reducedMotion.scrollAnimationDuration == 0)
    }

    private static func checkProgrammaticPresentation() {
        let cpuScreenshot = PanelPresentationState<String>(visibleDetailsMetric: "cpu")
        expect(cpuScreenshot.visibleDetailsMetric == "cpu")
        expect(cpuScreenshot.showsExpandedContent(for: "cpu", expandedMetric: "cpu"))
        expect(!cpuScreenshot.showsExpandedContent(for: "memory", expandedMetric: "cpu"))

        let collapsed = PanelPresentationState<String>()
        expect(!collapsed.showsExpandedContent(for: "cpu", expandedMetric: "cpu"))
    }

    private static func expect(
        _ condition: @autoclosure () -> Bool,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        guard condition() else {
            fatalError("Check failed", file: file, line: line)
        }
    }
}
