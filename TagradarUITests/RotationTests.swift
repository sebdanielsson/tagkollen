import UIKit
import XCTest

/// Rotates the running app and checks what a rotation must not break: the selected train stays
/// selected, and wherever the rotation lands in the regular layout, the sidebar comes in beside
/// the map. Nothing outside the app can rotate a simulator — `simctl` has no such command and
/// Simulator.app only takes it from its own menu — so this is the one place a size-class change is
/// exercised. It is worth running on an iPhone 17 Pro Max as well as an iPad: a Max is regular
/// width in landscape, so it takes the same layout.
///
/// The screen to start from is chosen with the same debug launch arguments `RootView` reads
/// (`-train`, `-station`, `-save`). `xcodebuild` strips the `TEST_RUNNER_` prefix and passes the
/// rest to the test runner's environment:
///
///     xcodebuild test -scheme TagradarUITests -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' \
///         TEST_RUNNER_TAGRADAR_LAUNCH_ARGS="-train 520"
///
/// `XCUIDevice` asks the app to rotate; it does not rotate the simulated display, and the request
/// is dropped often enough — most reliably on a simulator that has been running a while — that the
/// landscape half skips rather than fails when the window did not actually re-lay out. Boot the
/// device fresh for a run that exercises it. The attached screenshots are for diagnosis only: they
/// show the app's new layout drawn into the old frame, so they are not layout references.
final class RotationTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = true
    }

    @MainActor
    func testSelectionAndSidebarSurviveRotation() throws {
        let environment = ProcessInfo.processInfo.environment
        let arguments = (environment["TAGRADAR_LAUNCH_ARGS"] ?? "").split(separator: " ").map(String.init)
        // Seconds for the map, the live stream and the timetable to settle after each pose change.
        let settle = UInt32(environment["TAGRADAR_SETTLE"] ?? "") ?? 10

        let app = XCUIApplication()
        // Pinned to the source language: every label this test looks up is localised, and the
        // simulator's own language would otherwise decide whether the queries match.
        app.launchArguments = arguments + ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        defer { XCUIDevice.shared.orientation = .portrait }

        let poses: [(name: String, orientation: UIDeviceOrientation)] = [
            ("portrait", .portrait),
            ("landscape", .landscapeLeft),
        ]
        for pose in poses {
            XCUIDevice.shared.orientation = pose.orientation
            sleep(settle)
            let window = app.windows.firstMatch.frame
            print("[RotationTests] \(pose.name): window \(window)")
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = pose.name
            attachment.lifetime = .keepAlways
            add(attachment)

            if let train = Self.trainNumber(in: arguments) {
                // The detail's title, whether it is in the compact card or the regular inspector.
                let title = app.staticTexts["Train \(train)"]
                XCTAssertTrue(
                    title.waitForExistence(timeout: 5),
                    "train \(train)'s detail should be showing in \(pose.name)"
                )
            }
            guard pose.orientation.isLandscape else { continue }
            try XCTSkipUnless(
                window.width > window.height,
                "the simulator ignored the rotation request, so the landscape layout was never laid out"
            )
            // The sidebar toggle exists only in the regular layout, so it says which layout this
            // device landed in without assuming an idiom: an iPhone Max is regular in landscape
            // too, while a smaller iPhone stays on the card and has nothing to assert.
            let isRegular = app.buttons["Sidebar"].waitForExistence(timeout: 5)
            print("[RotationTests] landscape layout: \(isRegular ? "regular, asserting the sidebar" : "compact, nothing to assert")")
            guard isRegular else { continue }
            // The sidebar's search field is the one thing only the sidebar has.
            let search = app.textFields["Train number or station"]
            XCTAssertTrue(
                search.waitForExistence(timeout: 5) && search.isHittable,
                "the sidebar should be on screen beside the map in landscape"
            )
        }
    }

    /// The number from `-train <number>` or `-train <number>@<yyyy-MM-dd>`.
    private static func trainNumber(in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: "-train"), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1].split(separator: "@").first.map(String.init)
    }
}
