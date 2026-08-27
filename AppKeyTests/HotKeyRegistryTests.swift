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

    func testRegisterAvailableKeepsSuccessfulRegistrationsAfterConflict() {
        enum Failure: Error { case conflict }
        var registered: [String] = ["stale"]

        let errors = HotKeyRegistrationTransaction.registerAvailable(
            desired: ["first", "conflict", "last"],
            unregisterAll: { registered.removeAll() },
            register: { item in
                if item == "conflict" { throw Failure.conflict }
                registered.append(item)
            }
        )

        XCTAssertEqual(registered, ["first", "last"])
        XCTAssertEqual(errors.count, 1)
    }
}
