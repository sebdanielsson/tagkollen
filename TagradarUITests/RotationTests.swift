import UIKit
import XCTest

/// Rotates the running app and checks what a rotation must not break: the selected train stays
/// selected, and on iPad the landscape layout brings the sidebar in beside the map. Nothing
/// outside the app can rotate a simulator — `simctl` has no such command and Simulator.app only
/// takes it from its own menu — so this is the one place a size-class change is exercised.
///
/// The screen to start from is chosen with the same debug launch arguments `RootView` reads
/// (`-train`, `-station`, `-save`), passed through the test runner's environment:
///
///     xcodebuild test -scheme TagradarUITests -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' \
///         TEST_RUNNER_TAGRADAR_LAUNCH_ARGS="-train 520"
///
/// A screenshot per pose is attached for diagnosis only. `XCUIDevice` rotates what the app is
/// told, not the simulated display, so those images show the app's new layout drawn into the old
/// frame; they are not layout references.
final class RotationTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = true
    }

    @MainActor
    func testSelectionAndSidebarSurviveRotation() {
        let environment = ProcessInfo.processInfo.environment
        let arguments = (environment["TAGRADAR_LAUNCH_ARGS"] ?? "").split(separator: " ").map(String.init)
        // Seconds for the map, the live stream and the timetable to settle after each pose change.
        let settle = UInt32(environment["TAGRADAR_SETTLE"] ?? "") ?? 10
        let isPad = UIDevice.current.userInterfaceIdiom == .pad

        let app = XCUIApplication()
        app.launchArguments = arguments
        XCUIDevice.shared.orientation = .portrait
        app.launch()

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
                // The detail's title, whether it is in the iPhone card or the iPad inspector.
                let title = app.staticTexts["Train \(train)"]
                XCTAssertTrue(
                    title.waitForExistence(timeout: 5),
                    "train \(train)'s detail should be showing in \(pose.name)"
                )
            }
            if isPad, pose.orientation.isLandscape {
                // The sidebar is hidden in portrait and shown in landscape; its search field is
                // the one thing only the sidebar has.
                let search = app.textFields["Train number or station"]
                XCTAssertTrue(
                    search.waitForExistence(timeout: 5) && search.isHittable,
                    "the sidebar should be on screen beside the map in landscape"
                )
                XCTAssertGreaterThan(window.width, window.height, "the window should have re-laid out for landscape")
            }
        }
        XCUIDevice.shared.orientation = .portrait
    }

    /// The number from `-train <number>` or `-train <number>@<yyyy-MM-dd>`.
    private static func trainNumber(in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: "-train"), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1].split(separator: "@").first.map(String.init)
    }
}
