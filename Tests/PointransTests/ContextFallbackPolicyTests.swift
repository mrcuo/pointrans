import XCTest

final class ContextFallbackPolicyTests: XCTestCase {
    func testUnavailableAndRecoverableErrorsUseCloud() {
        XCTAssertTrue(ContextFallbackPolicy.shouldUseCloud(after: .unavailable))
        XCTAssertTrue(ContextFallbackPolicy.shouldUseCloud(after: .transient))
    }

    func testCancellationInvalidInputAndSafetyRefusalNeverUseCloud() {
        XCTAssertFalse(ContextFallbackPolicy.shouldUseCloud(after: .cancelled))
        XCTAssertFalse(ContextFallbackPolicy.shouldUseCloud(after: .invalidInput))
        XCTAssertFalse(ContextFallbackPolicy.shouldUseCloud(after: .safetyRefusal))
    }

    func testQuotaAndAuthDoNotLoopBackToCloud() {
        XCTAssertFalse(ContextFallbackPolicy.shouldUseCloud(after: .quotaExhausted(resetAt: nil)))
        XCTAssertFalse(ContextFallbackPolicy.shouldUseCloud(after: .unauthorized))
    }
}
