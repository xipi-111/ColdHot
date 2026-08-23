import Foundation

@main
enum DynamicBackgroundRevealCheck {
    static func main() {
        checkPosterPolicy()
        checkOpaqueUntilFirstFrame()
        checkResetRestoresOpaqueMask()
        print("Dynamic background reveal checks passed")
    }

    private static func checkPosterPolicy() {
        expect(PanelBackgroundPosterPolicy.showsPoster(
            mediaKind: .staticImage,
            reduceMotion: false
        ))
        expect(!PanelBackgroundPosterPolicy.showsPoster(
            mediaKind: .video,
            reduceMotion: false
        ))
        expect(!PanelBackgroundPosterPolicy.showsPoster(
            mediaKind: .convertedGIF,
            reduceMotion: false
        ))
        expect(PanelBackgroundPosterPolicy.showsPoster(
            mediaKind: .video,
            reduceMotion: true
        ))
    }

    private static func checkOpaqueUntilFirstFrame() {
        var state = DynamicBackgroundRevealState()
        expect(state.maskOpacity == 1)
        expect(state.animationDuration == 0)

        state.receive(isReadyForDisplay: false)
        expect(state.maskOpacity == 1)
        expect(state.animationDuration == 0)

        state.receive(isReadyForDisplay: true)
        expect(state.maskOpacity == 0)
        expect(state.animationDuration == 0.4)
    }

    private static func checkResetRestoresOpaqueMask() {
        var state = DynamicBackgroundRevealState()
        state.receive(isReadyForDisplay: true)
        state.reset()

        expect(state.maskOpacity == 1)
        expect(state.animationDuration == 0)
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
