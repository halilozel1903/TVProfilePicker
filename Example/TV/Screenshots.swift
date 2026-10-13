import Foundation
import SwiftUI

/// Scenes used by CI to capture the README screenshots on an Apple TV simulator.
/// Launch with `-screenshot <scene>`; normal launches are unaffected.
///
/// Every scene shows the package's real views with the demo household from `DemoProfiles`
/// (generic made-up names). Nothing is loaded from the network.
enum ScreenshotScene: String {
    /// The picker, with focus on Jordan (the profile chosen last).
    case picker
    /// The PIN pad for Sam's locked profile, with two digits typed.
    case pin
    /// The editor for Sam's profile: name, avatar, kids setting, PIN lock and delete.
    case edit
    /// The avatar chooser for Casey's profile.
    case avatar

    static var current: ScreenshotScene? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-screenshot"), arguments.indices.contains(index + 1) else {
            return nil
        }
        return ScreenshotScene(rawValue: arguments[index + 1])
    }
}

extension View {
    /// Tells scripts/screenshots.sh that the scene is on screen by writing `tmp/screenshot-ready`
    /// into the app container, once default focus has landed and the focus animation has ended.
    func signalsScreenshotReady(_ scene: ScreenshotScene?) -> some View {
        task {
            guard let scene else { return }
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            let marker = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("screenshot-ready")
            try? scene.rawValue.write(to: marker, atomically: true, encoding: .utf8)
        }
    }
}
