import XCTest
@testable import MyCodeAssistantHost

final class UISettingsManagerTests: XCTestCase {
    func testDefaultsLoad() {
        let s = UISettingsManager.shared.settings
        XCTAssertFalse(s.gpt5ApiUrl.isEmpty)
        XCTAssertFalse(s.gpt5Model.isEmpty)
        XCTAssertGreaterThan(s.requestTimeout, 0)
    }
}