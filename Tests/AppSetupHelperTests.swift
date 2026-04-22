import AppKit
import XCTest

@testable import Whisp

final class AppSetupHelperTests: XCTestCase {
    func testConfigureLaunchActivationPolicyUsesRegularAppMode() {
        var requestedPolicy: NSApplication.ActivationPolicy?

        let result = AppSetupHelper.configureLaunchActivationPolicy(
            appIsReady: true,
            setActivationPolicy: { activationPolicy in
                requestedPolicy = activationPolicy
                return true
            }
        )

        XCTAssertTrue(result)
        XCTAssertEqual(requestedPolicy, .regular)
    }

    func testConfigureLaunchActivationPolicySkipsWhenAppIsNotReady() {
        var setActivationPolicyCalls = 0

        let result = AppSetupHelper.configureLaunchActivationPolicy(
            appIsReady: false,
            setActivationPolicy: { _ in
                setActivationPolicyCalls += 1
                return true
            }
        )

        XCTAssertFalse(result)
        XCTAssertEqual(setActivationPolicyCalls, 0)
    }
}
