import Foundation
import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

@main
enum PanelBackgroundCheck {
    @MainActor
    static func main() throws {
        checkSettingsPersistence()
        checkBackgroundTransformGeometry()
        try checkPreviewLiveTransformWiring()
        try runAsyncCheck {
            try await checkImageLifecycle()
        }
        checkBackgroundRendering()
        checkReadabilityRendering()
        checkPanelPreviewRendering()
        checkLiveScrollIndicatorSuppression()
        checkCollapsedScrollLock()
        if CommandLine.arguments.count == 3 {
            try writePreviewSnapshot(
                backgroundPath: CommandLine.arguments[1],
                outputPath: CommandLine.arguments[2]
            )
        }
        print("Panel background checks passed")
    }

    @MainActor
    private static func runAsyncCheck(
        _ operation: @escaping @MainActor () async throws -> Void
    ) throws {
        let resultBox = PanelBackgroundAsyncResultBox()
        Task { @MainActor in
            do {
                try await operation()
                resultBox.result = .success(())
            } catch {
                resultBox.result = .failure(error)
            }
        }
        while resultBox.result == nil {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        try resultBox.result?.get()
    }

    private static func checkSettingsPersistence() {
        let suiteName = "com.xipiyoung.ColdHot.panel-background-check"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Unable to create isolated defaults suite")
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let initial = MonitorSettings(defaults: defaults)
        expect(!initial.isPanelBackgroundEnabled)
        expect(initial.panelBackgroundDimOpacity == 0.35)
        expect(initial.panelCardOpacity == 1)
        expect(initial.panelPrimaryTextOpacity == 1)
        expect(initial.panelSecondaryTextOpacity == 1)
        expect(initial.panelProgressOpacity == 1)
        expect(initial.panelBackgroundZoom == 1)
        expect(initial.panelBackgroundPositionX == 0)
        expect(initial.panelBackgroundPositionY == 0)

        initial.setPanelBackgroundZoom(1.5)
        initial.setPanelBackgroundPosition(x: 0.4, y: -0.6)
        initial.didReplacePanelBackgroundImage()
        expect(initial.isPanelBackgroundEnabled)
        expect(initial.panelBackgroundZoom == 1)
        expect(initial.panelBackgroundPositionX == 0)
        expect(initial.panelBackgroundPositionY == 0)

        initial.setPanelBackgroundZoom(1.8)
        initial.setPanelBackgroundPosition(x: -0.7, y: 0.3)
        initial.didRemovePanelBackgroundImage()
        expect(!initial.isPanelBackgroundEnabled)
        expect(initial.panelBackgroundZoom == 1)
        expect(initial.panelBackgroundPositionX == 0)
        expect(initial.panelBackgroundPositionY == 0)

        initial.setPanelBackgroundEnabled(true)
        initial.setPanelBackgroundDimOpacity(1)
        initial.setPanelCardOpacity(2)
        initial.setPanelPrimaryTextOpacity(2)
        initial.setPanelSecondaryTextOpacity(2)
        initial.setPanelProgressOpacity(2)
        initial.setPanelBackgroundZoom(3)
        initial.setPanelBackgroundPosition(x: -2, y: 2)

        let restored = MonitorSettings(defaults: defaults)
        expect(restored.isPanelBackgroundEnabled)
        expect(restored.panelBackgroundDimOpacity == 0.70)
        expect(restored.panelCardOpacity == 1)
        expect(restored.panelPrimaryTextOpacity == 1)
        expect(restored.panelSecondaryTextOpacity == 1)
        expect(restored.panelProgressOpacity == 1)
        expect(restored.panelBackgroundZoom == 2)
        expect(restored.panelBackgroundPositionX == -1)
        expect(restored.panelBackgroundPositionY == 1)

        restored.setPanelBackgroundZoom(.nan)
        restored.setPanelBackgroundPosition(x: .nan, y: .nan)
        expect(restored.panelBackgroundZoom == 2)
        expect(restored.panelBackgroundPositionX == -1)
        expect(restored.panelBackgroundPositionY == 1)

        restored.resetPanelBackgroundTransform()
        expect(restored.panelBackgroundZoom == 1)
        expect(restored.panelBackgroundPositionX == 0)
        expect(restored.panelBackgroundPositionY == 0)

        restored.setPanelBackgroundDimOpacity(-1)
        restored.setPanelCardOpacity(0)
        restored.setPanelPrimaryTextOpacity(0)
        restored.setPanelSecondaryTextOpacity(0)
        restored.setPanelProgressOpacity(0)
        expect(restored.panelBackgroundDimOpacity == 0)
        expect(restored.panelCardOpacity == 0.10)
        expect(restored.panelPrimaryTextOpacity == 0.50)
        expect(restored.panelSecondaryTextOpacity == 0.50)
        expect(restored.panelProgressOpacity == 0.50)

        restored.reset()
        expect(!restored.isPanelBackgroundEnabled)
        expect(restored.panelBackgroundDimOpacity == 0.35)
        expect(restored.panelCardOpacity == 1)
        expect(restored.panelPrimaryTextOpacity == 1)
        expect(restored.panelSecondaryTextOpacity == 1)
        expect(restored.panelProgressOpacity == 1)
        expect(restored.panelBackgroundZoom == 1)
        expect(restored.panelBackgroundPositionX == 0)
        expect(restored.panelBackgroundPositionY == 0)

        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(0.65, forKey: "panelTextOpacity")

        let migrated = MonitorSettings(defaults: defaults)
        expect(migrated.panelPrimaryTextOpacity == 0.65)
        expect(migrated.panelSecondaryTextOpacity == 0.65)
        expect(migrated.panelProgressOpacity == 1)

        migrated.setPanelPrimaryTextOpacity(0.80)
        let migratedRestored = MonitorSettings(defaults: defaults)
        expect(migratedRestored.panelPrimaryTextOpacity == 0.80)
        expect(migratedRestored.panelSecondaryTextOpacity == 0.65)
    }

    private static func checkBackgroundTransformGeometry() {
        let centered = PanelBackgroundTransform.resolve(
            imageSize: CGSize(width: 200, height: 100),
            containerSize: CGSize(width: 100, height: 100),
            zoom: 1,
            position: CGPoint(x: 0, y: 0)
        )
        expect(centered.renderedSize == CGSize(width: 200, height: 100))
        expect(centered.maximumOffset == CGSize(width: 50, height: 0))
        expect(centered.offset == .zero)

        let rightEdge = PanelBackgroundTransform.resolve(
            imageSize: CGSize(width: 200, height: 100),
            containerSize: CGSize(width: 100, height: 100),
            zoom: 1,
            position: CGPoint(x: 1, y: 0)
        )
        expect(rightEdge.offset == CGSize(width: 50, height: 0))

        let zoomed = PanelBackgroundTransform.resolve(
            imageSize: CGSize(width: 200, height: 100),
            containerSize: CGSize(width: 100, height: 100),
            zoom: 2,
            position: CGPoint(x: -1, y: 1)
        )
        expect(zoomed.renderedSize == CGSize(width: 400, height: 200))
        expect(zoomed.maximumOffset == CGSize(width: 150, height: 50))
        expect(zoomed.offset == CGSize(width: -150, height: 50))

        let clamped = PanelBackgroundTransform.resolve(
            imageSize: CGSize(width: 100, height: 200),
            containerSize: CGSize(width: 100, height: 100),
            zoom: 9,
            position: CGPoint(x: -9, y: 9)
        )
        expect(clamped.zoom == 2)
        expect(clamped.position == CGPoint(x: -1, y: 1))
        expect(clamped.renderedSize.width >= 100)
        expect(clamped.renderedSize.height >= 100)

        let dragged = PanelBackgroundTransform.draggedPosition(
            from: .zero,
            translation: CGSize(width: 25, height: 30),
            maximumOffset: CGSize(width: 50, height: 0)
        )
        expect(dragged == CGPoint(x: 0.5, y: 0))

        let position = CGPoint(x: 0.2, y: -0.3)
        expectPointsEqual(
            PanelBackgroundPositionAdjustment.nudged(position, direction: .left),
            CGPoint(x: 0.175, y: -0.3)
        )
        expectPointsEqual(
            PanelBackgroundPositionAdjustment.nudged(position, direction: .right),
            CGPoint(x: 0.225, y: -0.3)
        )
        expectPointsEqual(
            PanelBackgroundPositionAdjustment.nudged(position, direction: .up),
            CGPoint(x: 0.2, y: -0.325)
        )
        expectPointsEqual(
            PanelBackgroundPositionAdjustment.nudged(position, direction: .down),
            CGPoint(x: 0.2, y: -0.275)
        )
        expectPointsEqual(
            PanelBackgroundPositionAdjustment.nudged(
                CGPoint(x: -0.99, y: 0.99),
                direction: .left,
                step: 0.1
            ),
            CGPoint(x: -1, y: 0.99)
        )
        expectPointsEqual(
            PanelBackgroundPositionAdjustment.nudged(
                CGPoint(x: -0.99, y: 0.99),
                direction: .down,
                step: 0.1
            ),
            CGPoint(x: -0.99, y: 1)
        )
    }

    private static func checkPreviewLiveTransformWiring() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let dashboard = try String(
            contentsOf: repositoryRoot.appendingPathComponent("ColdHot/Views/DashboardView.swift"),
            encoding: .utf8
        )
        let preview = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "ColdHot/Views/PanelAppearancePreview.swift"
            ),
            encoding: .utf8
        )
        let settings = try String(
            contentsOf: repositoryRoot.appendingPathComponent("ColdHot/Views/SettingsView.swift"),
            encoding: .utf8
        )

        expect(dashboard.contains("zoom: settings.panelBackgroundZoom"))
        expect(dashboard.contains("x: settings.panelBackgroundPositionX"))
        expect(dashboard.contains("y: settings.panelBackgroundPositionY"))
        expect(preview.contains("zoom: backgroundZoom"))
        expect(preview.contains("position: backgroundPosition"))
        expect(settings.contains("backgroundZoom: settings.panelBackgroundZoom"))
        expect(settings.contains("backgroundPosition: panelBackgroundPosition"))
    }

    @MainActor
    private static func checkImageLifecycle() async throws {
        let fileManager = FileManager.default
        let rootDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("ColdHotPanelBackgroundCheck-\(UUID().uuidString)")
        try fileManager.createDirectory(
            at: rootDirectory,
            withIntermediateDirectories: true
        )
        defer { try? fileManager.removeItem(at: rootDirectory) }

        let sourceURL = rootDirectory.appendingPathComponent("source.png")
        try writeTestPNG(
            to: sourceURL,
            width: 2_400,
            height: 1_200,
            color: .systemRed
        )

        let storeDirectory = rootDirectory.appendingPathComponent("store")
        let store = PanelBackgroundStore(directoryURL: storeDirectory)
        expect(!store.hasImage)

        try await store.importBackground(from: sourceURL)
        expect(store.hasImage)
        let storedURL = try committedMediaURL(in: storeDirectory)
        let storedPixelSize = try pixelSize(of: storedURL)
        expect(storedPixelSize == CGSize(width: 1_600, height: 800))

        let smallSourceURL = rootDirectory.appendingPathComponent("small-source.png")
        try writeTestPNG(
            to: smallSourceURL,
            width: 320,
            height: 200,
            color: .systemBlue
        )
        try await store.importBackground(from: smallSourceURL)
        let smallStoredURL = try committedMediaURL(in: storeDirectory)
        let smallStoredPixelSize = try pixelSize(of: smallStoredURL)
        expect(smallStoredPixelSize == CGSize(width: 320, height: 200))

        let storedBeforeInvalidImport = try Data(contentsOf: smallStoredURL)
        let invalidURL = rootDirectory.appendingPathComponent("invalid.txt")
        try Data("not an image".utf8).write(to: invalidURL)
        do {
            try await store.importBackground(from: invalidURL)
            fatalError("Invalid image import should fail")
        } catch {}
        expect(store.hasImage)
        let storedAfterInvalidImport = try Data(contentsOf: smallStoredURL)
        expect(storedAfterInvalidImport == storedBeforeInvalidImport)

        let restored = PanelBackgroundStore(directoryURL: storeDirectory)
        expect(restored.hasImage)
        expect(restored.image != nil)

        try fileManager.removeItem(at: smallStoredURL)
        expect(restored.hasImage)
        let missingFileStore = PanelBackgroundStore(directoryURL: storeDirectory)
        expect(!missingFileStore.hasImage)

        try restored.removeBackground()
        expect(!restored.hasImage)
        expect(!fileManager.fileExists(atPath: smallStoredURL.path))
        expect(
            !fileManager.fileExists(
                atPath: storeDirectory.appendingPathComponent("manifest.json").path
            )
        )
    }

    private static func committedMediaURL(in directory: URL) throws -> URL {
        let data = try Data(contentsOf: directory.appendingPathComponent("manifest.json"))
        let manifest = try JSONDecoder().decode(PanelBackgroundManifest.self, from: data)
        return directory.appendingPathComponent(manifest.mediaFilename)
    }

    private static func writeTestPNG(
        to url: URL,
        width: Int,
        height: Int,
        color: NSColor
    ) throws {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue
            | CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            fatalError("Unable to create test image context")
        }
        context.setFillColor(color.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(
                url as CFURL,
                UTType.png.identifier as CFString,
                1,
                nil
              ) else {
            fatalError("Unable to create test PNG destination")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            fatalError("Unable to write test PNG")
        }
    }

    private static func pixelSize(of url: URL) throws -> CGSize {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber else {
            fatalError("Unable to inspect image dimensions")
        }
        return CGSize(width: width.doubleValue, height: height.doubleValue)
    }

    @MainActor
    private static func checkBackgroundRendering() {
        let image = solidImage(width: 100, height: 100, color: .systemRed)
        let clearPixel = renderCenterPixel(image: image, dimOpacity: 0)
        let dimmedPixel = renderCenterPixel(image: image, dimOpacity: 0.35)

        expect(clearPixel.redComponent > 0.9)
        expect(clearPixel.redComponent > clearPixel.greenComponent)
        expect(dimmedPixel.redComponent < clearPixel.redComponent * 0.8)
        expect(dimmedPixel.redComponent > dimmedPixel.greenComponent)

        let splitImage = horizontalSplitImage(
            width: 200,
            height: 100,
            leftColor: .systemRed,
            rightColor: .systemBlue
        )
        let imageDraggedRight = renderCenterPixel(
            image: splitImage,
            dimOpacity: 0,
            zoom: 1,
            position: CGPoint(x: 1, y: 0)
        )
        let imageDraggedLeft = renderCenterPixel(
            image: splitImage,
            dimOpacity: 0,
            zoom: 1,
            position: CGPoint(x: -1, y: 0)
        )
        expect(imageDraggedRight.redComponent > imageDraggedRight.blueComponent)
        expect(imageDraggedLeft.blueComponent > imageDraggedLeft.redComponent)
    }

    @MainActor
    private static func checkReadabilityRendering() {
        let opaqueCard = renderCardCenterPixel(
            cardOpacity: 1,
            usesCustomBackground: true
        )
        let translucentCard = renderCardCenterPixel(
            cardOpacity: 0.10,
            usesCustomBackground: true
        )
        let nativeCard = renderCardCenterPixel(
            cardOpacity: 0.10,
            usesCustomBackground: false
        )

        expect(translucentCard.redComponent > opaqueCard.redComponent)
        expect(abs(nativeCard.redComponent - opaqueCard.redComponent) < 0.05)

        let fullPrimary = renderTextCenterPixel(
            role: .primary,
            primaryTextOpacity: 1,
            secondaryTextOpacity: 1,
            usesCustomBackground: true
        )
        let dimmedPrimary = renderTextCenterPixel(
            role: .primary,
            primaryTextOpacity: 0.50,
            secondaryTextOpacity: 1,
            usesCustomBackground: true
        )
        let unaffectedSecondary = renderTextCenterPixel(
            role: .secondary,
            primaryTextOpacity: 0.50,
            secondaryTextOpacity: 1,
            usesCustomBackground: true
        )
        let dimmedSecondary = renderTextCenterPixel(
            role: .secondary,
            primaryTextOpacity: 1,
            secondaryTextOpacity: 0.50,
            usesCustomBackground: true
        )
        let unaffectedPrimary = renderTextCenterPixel(
            role: .primary,
            primaryTextOpacity: 1,
            secondaryTextOpacity: 0.50,
            usesCustomBackground: true
        )
        let nativeText = renderTextCenterPixel(
            role: .primary,
            primaryTextOpacity: 0.50,
            secondaryTextOpacity: 0.50,
            usesCustomBackground: false
        )

        expect(brightness(of: fullPrimary) > 0.90)
        expect(brightness(of: dimmedPrimary) < brightness(of: fullPrimary) * 0.75)
        expect(brightness(of: unaffectedSecondary) > 0.90)
        expect(brightness(of: dimmedSecondary) < brightness(of: fullPrimary) * 0.75)
        expect(brightness(of: unaffectedPrimary) > 0.90)
        expect(brightness(of: nativeText) > 0.90)

        let fullProgress = renderProgressCenterPixel(
            progressOpacity: 1,
            usesCustomBackground: true
        )
        let dimmedProgress = renderProgressCenterPixel(
            progressOpacity: 0.50,
            usesCustomBackground: true
        )
        let nativeProgress = renderProgressCenterPixel(
            progressOpacity: 0.50,
            usesCustomBackground: false
        )

        expect(brightness(of: fullProgress) > 0.90)
        expect(brightness(of: dimmedProgress) < brightness(of: fullProgress) * 0.75)
        expect(brightness(of: nativeProgress) > 0.90)
    }

    @MainActor
    private static func checkPanelPreviewRendering() {
        let preview = PanelAppearancePreview(
            image: solidImage(width: 800, height: 1_200, color: .systemBlue),
            isBackgroundEnabled: true,
            dimOpacity: 0.35,
            backgroundZoom: 1.4,
            backgroundPosition: CGPoint(x: -0.25, y: 0.5),
            cardOpacity: 0.80,
            primaryTextOpacity: 0.90,
            secondaryTextOpacity: 0.70,
            progressOpacity: 0.60,
            enabledMetrics: MetricKind.allCases,
            showsDockQuickControl: true
        )
        let hostingView = NSHostingView(rootView: preview.fixedSize())
        let size = hostingView.fittingSize
        hostingView.frame = CGRect(origin: .zero, size: size)
        hostingView.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        expect(abs(size.width - 370) < 1)
        expect(size.height > size.width)
        expect(
            PanelLayout.metricsViewportHeight(
                metricCount: MetricKind.allCases.count,
                hasExpandedMetric: false
            ) == 512
        )

        let scrollViews = descendants(of: hostingView).compactMap { $0 as? NSScrollView }
        guard let metricsScrollView = scrollViews.max(by: {
            $0.contentView.bounds.height < $1.contentView.bounds.height
        }) else {
            fatalError("Unable to locate metrics scroll view")
        }
        let viewportHeight = metricsScrollView.contentView.bounds.height
        let documentHeight = metricsScrollView.documentView?.bounds.height ?? .infinity
        expect(viewportHeight >= 511)
        expect(documentHeight <= viewportHeight + 1)
        expect(!metricsScrollView.hasVerticalScroller)

    }

    @MainActor
    private static func checkLiveScrollIndicatorSuppression() {
        let hostingView = NSHostingView(rootView: LivePanelScrollHarness(allowsScrolling: true))
        hostingView.frame = CGRect(x: 0, y: 0, width: 370, height: 200)
        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        defer { window.close() }
        window.layoutIfNeeded()
        hostingView.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.10))

        let scrollViews = descendants(of: hostingView).compactMap { $0 as? NSScrollView }
        guard let scrollView = scrollViews.max(by: {
            ($0.documentView?.bounds.height ?? 0)
                < ($1.documentView?.bounds.height ?? 0)
        }) else {
            fatalError("Unable to locate live panel scroll view")
        }
        let viewportHeight = scrollView.contentView.bounds.height
        let documentHeight = scrollView.documentView?.bounds.height ?? 0
        expect(documentHeight > viewportHeight)
        expect(!scrollView.hasVerticalScroller)

        // Reproduce the live-menu failure: AppKit restores the indicator as
        // a scroll gesture begins after SwiftUI has rebuilt the ScrollView.
        scrollView.hasVerticalScroller = true
        NotificationCenter.default.post(
            name: NSScrollView.willStartLiveScrollNotification,
            object: scrollView
        )
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        expect(!scrollView.hasVerticalScroller)
    }

    @MainActor
    private static func checkCollapsedScrollLock() {
        let hostingView = NSHostingView(
            rootView: LivePanelScrollHarness(allowsScrolling: false)
        )
        hostingView.frame = CGRect(x: 0, y: 0, width: 370, height: 200)
        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        defer { window.close() }
        window.layoutIfNeeded()
        hostingView.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.10))

        let scrollViews = descendants(of: hostingView).compactMap { $0 as? NSScrollView }
        guard let scrollView = scrollViews.max(by: {
            ($0.documentView?.bounds.height ?? 0)
                < ($1.documentView?.bounds.height ?? 0)
        }) else {
            fatalError("Unable to locate locked panel scroll view")
        }

        scrollView.contentView.scroll(to: NSPoint(x: 0, y: 120))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        NotificationCenter.default.post(
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        expect(abs(scrollView.contentView.bounds.origin.y) < 0.5)
    }

    @MainActor
    private static func writePreviewSnapshot(
        backgroundPath: String,
        outputPath: String
    ) throws {
        guard let image = NSImage(contentsOfFile: backgroundPath) else {
            fatalError("Unable to load preview background")
        }
        let preview = PanelAppearancePreview(
            image: image,
            isBackgroundEnabled: true,
            dimOpacity: 0.35,
            backgroundZoom: 1.4,
            backgroundPosition: CGPoint(x: -0.25, y: 0.5),
            cardOpacity: 0.80,
            primaryTextOpacity: 1,
            secondaryTextOpacity: 0.75,
            progressOpacity: 0.80,
            enabledMetrics: MetricKind.allCases,
            showsDockQuickControl: true
        )
        let hostingView = NSHostingView(rootView: preview.fixedSize())
        let size = hostingView.fittingSize
        hostingView.frame = CGRect(origin: .zero, size: size)
        hostingView.layoutSubtreeIfNeeded()

        guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(
            in: hostingView.bounds
        ) else {
            fatalError("Unable to create preview snapshot bitmap")
        }
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            fatalError("Unable to encode preview snapshot")
        }
        try data.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
    }

    @MainActor
    private static func renderCardCenterPixel(
        cardOpacity: Double,
        usesCustomBackground: Bool
    ) -> NSColor {
        let content = ZStack {
            Color.red
            PanelCardBackground(cornerRadius: 0)
        }
        .panelReadability(
            cardOpacity: cardOpacity,
            primaryTextOpacity: 1,
            secondaryTextOpacity: 1,
            progressOpacity: 1,
            usesCustomBackground: usesCustomBackground
        )
        return renderCenterPixel(content)
    }

    @MainActor
    private static func renderTextCenterPixel(
        role: PanelTextRole,
        primaryTextOpacity: Double,
        secondaryTextOpacity: Double,
        usesCustomBackground: Bool
    ) -> NSColor {
        let content = ZStack {
            Color.black
            Color.white
                .frame(width: 60, height: 60)
                .panelTextReadability(role)
        }
        .panelReadability(
            cardOpacity: 1,
            primaryTextOpacity: primaryTextOpacity,
            secondaryTextOpacity: secondaryTextOpacity,
            progressOpacity: 1,
            usesCustomBackground: usesCustomBackground
        )
        return renderCenterPixel(content)
    }

    @MainActor
    private static func renderProgressCenterPixel(
        progressOpacity: Double,
        usesCustomBackground: Bool
    ) -> NSColor {
        let content = ZStack {
            Color.black
            Color.white
                .frame(width: 60, height: 60)
                .panelProgressReadability()
        }
        .panelReadability(
            cardOpacity: 1,
            primaryTextOpacity: 1,
            secondaryTextOpacity: 1,
            progressOpacity: progressOpacity,
            usesCustomBackground: usesCustomBackground
        )
        return renderCenterPixel(content)
    }

    @MainActor
    private static func renderCenterPixel<Content: View>(
        _ content: Content
    ) -> NSColor {
        let side: CGFloat = 100
        let hostingView = NSHostingView(
            rootView: content.frame(width: side, height: side)
        )
        hostingView.frame = CGRect(x: 0, y: 0, width: side, height: side)
        hostingView.layoutSubtreeIfNeeded()

        guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(
            in: hostingView.bounds
        ) else {
            fatalError("Unable to create readability render bitmap")
        }
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        guard let color = bitmap.colorAt(
            x: bitmap.pixelsWide / 2,
            y: bitmap.pixelsHigh / 2
        )?.usingColorSpace(.deviceRGB) else {
            fatalError("Unable to sample readability render")
        }
        return color
    }

    private static func descendants(of view: NSView) -> [NSView] {
        view.subviews.flatMap { subview in
            [subview] + descendants(of: subview)
        }
    }

    @MainActor
    private static func renderCenterPixel(
        image: NSImage,
        dimOpacity: Double,
        zoom: Double = 1,
        position: CGPoint = .zero
    ) -> NSColor {
        let side: CGFloat = 100
        let content = PanelBackgroundView(
            image: image,
            isEnabled: true,
            dimOpacity: dimOpacity,
            zoom: zoom,
            position: position
        )
        .frame(width: side, height: side)
        let hostingView = NSHostingView(rootView: content)
        hostingView.frame = CGRect(x: 0, y: 0, width: side, height: side)
        hostingView.layoutSubtreeIfNeeded()

        guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(
            in: hostingView.bounds
        ) else {
            fatalError("Unable to create background render bitmap")
        }
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        guard let color = bitmap.colorAt(
            x: bitmap.pixelsWide / 2,
            y: bitmap.pixelsHigh / 2
        )?.usingColorSpace(.deviceRGB) else {
            fatalError("Unable to sample background render")
        }
        return color
    }

    private static func solidImage(
        width: Int,
        height: Int,
        color: NSColor
    ) -> NSImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue
            | CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            fatalError("Unable to create solid image context")
        }
        context.setFillColor(color.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage() else {
            fatalError("Unable to create solid image")
        }
        return NSImage(
            cgImage: image,
            size: NSSize(width: width, height: height)
        )
    }

    private static func horizontalSplitImage(
        width: Int,
        height: Int,
        leftColor: NSColor,
        rightColor: NSColor
    ) -> NSImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue
            | CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            fatalError("Unable to create split image context")
        }
        context.setFillColor(leftColor.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
        context.setFillColor(rightColor.cgColor)
        context.fill(CGRect(x: width / 2, y: 0, width: width / 2, height: height))
        guard let image = context.makeImage() else {
            fatalError("Unable to create split image")
        }
        return NSImage(cgImage: image, size: NSSize(width: width, height: height))
    }

    private static func brightness(of color: NSColor) -> CGFloat {
        guard let rgb = color.usingColorSpace(.sRGB) else {
            fatalError("Unable to convert sampled color to sRGB")
        }
        return max(rgb.redComponent, rgb.greenComponent, rgb.blueComponent)
    }

    private static func expectPointsEqual(
        _ actual: CGPoint,
        _ expected: CGPoint,
        accuracy: CGFloat = 0.000_001,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        expect(
            abs(actual.x - expected.x) <= accuracy
                && abs(actual.y - expected.y) <= accuracy,
            file: file,
            line: line
        )
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

@MainActor
private final class PanelBackgroundAsyncResultBox {
    var result: Result<Void, Error>?
}

private struct LivePanelScrollHarness: View {
    let allowsScrolling: Bool

    var body: some View {
        ScrollViewReader { _ in
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(0..<20, id: \.self) { index in
                        Text("指标 \(index)")
                            .frame(maxWidth: .infinity)
                            .frame(height: 42)
                    }
                }
            }
            .scrollIndicators(.never)
            .hidePanelVerticalScrollIndicator(allowsScrolling: allowsScrolling)
        }
        .frame(width: 370, height: 200)
    }
}
