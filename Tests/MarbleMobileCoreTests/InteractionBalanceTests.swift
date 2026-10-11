import XCTest
@testable import MarbleMobileCore

final class InteractionBalanceTests: XCTestCase {
    func testPurchaseAndAcquisitionShowCurrentBalanceAfterCostWithOrWithoutCityDTO() throws {
        let city = InformationInfo(
            cityID: 3, cityName: "도쿄", ownerID: nil, groupName: "파랑",
            buildings: [], cityEffectTypes: [], isColorMonopoly: false,
            isFestival: false, hasOlympic: false
        )
        let citySources: [[Int: InformationInfo]] = [[:], [3: city]]

        for mission in ["purchase_city", "acquire_city"] {
            let request = try makeRequest(mission: mission)
            // These requests do not carry a balance. Their parser's default zero
            // must never replace the current game state's balance in the UI.
            XCTAssertEqual(request.ownedMarble, 0)

            for cityInformation in citySources {
                let text = InteractionRequestPresenter.description(
                    request, cityInformation: cityInformation, myPlayerID: 1,
                    ownedMarble: 350_000
                )
                XCTAssertTrue(text.hasSuffix("비용: 200,000마블\n보유 마블: 350,000마블"))
                XCTAssertEqual(text.components(separatedBy: "보유 마블:").count, 2)

                let entryText = InteractionRequestPresenter.entryText(
                    request, cityInformation: cityInformation, myPlayerID: 1,
                    ownedMarble: 350_000
                )
                XCTAssertEqual(entryText, text)
            }
        }
    }

    func testZeroBalanceIsShownAndMissingBalanceIsNotInvented() throws {
        for mission in ["purchase_city", "acquire_city"] {
            let request = try makeRequest(mission: mission)
            let zero = InteractionRequestPresenter.description(
                request, cityInformation: [:], myPlayerID: 1, ownedMarble: 0
            )
            XCTAssertTrue(zero.hasSuffix("\n보유 마블: 0마블"))

            let missing = InteractionRequestPresenter.description(
                request, cityInformation: [:], myPlayerID: 1
            )
            XCTAssertEqual(missing, request.description)
            XCTAssertFalse(missing.contains("보유 마블:"))
        }
    }

    func testOtherInteractionDescriptionsRemainUnchanged() throws {
        let request = try makeRequest(mission: "world_travel_offer")
        XCTAssertEqual(
            InteractionRequestPresenter.description(
                request, cityInformation: [:], myPlayerID: 1, ownedMarble: 350_000
            ),
            request.description
        )
    }

    private func makeRequest(mission: String) throws -> InteractionRequestSnapshot {
        let payload: [String: Any] = [
            "mission_type": mission, "city_id": 3, "city_name": "도쿄",
            "owner_id": 2, "owner_nickname": "강", "cost": 200_000,
        ]
        return try InteractionRequestParser.parse([
            "type": "interaction_request", "interaction_flow_id": "flow-balance",
            "request_id": "request-balance", "action_type": mission,
            "interaction_type": "confirm", "cancellable": true,
            "payload": payload,
        ])
    }
}
