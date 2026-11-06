import UIKit
import XCTest
import linkbud_flutter

final class RunnerTests: XCTestCase {
    func testUniversalLinkLifecycleCallbackIsExposedToFlutter() {
        XCTAssertTrue(LinkBudFlutterPlugin.instancesRespond(
            to: NSSelectorFromString("application:continueUserActivity:restorationHandler:")))
    }
}
