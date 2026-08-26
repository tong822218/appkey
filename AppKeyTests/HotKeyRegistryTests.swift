import XCTest
@testable import AppKey

final class HotKeyRegistryTests: XCTestCase {
    func testFailedReplacementRestoresPreviousRegistrations() {
        enum Failure: Error { case conflict }
        var registered: [String] = ["old-a", "old-b"]

        XCTAssertThrowsError(
            try HotKeyRegistrationTransaction.replace(
                previous: ["old-a", "old-b"],
                desired: ["new-a", "conflict"],
                unregisterAll: { registered.removeAll() },
                register: { item in
                    if item == "conflict" { throw Failure.conflict }
                    registered.append(item)
                }
            )
        )

        XCTAssertEqual(registered, ["old-a", "old-b"])
    }
}
