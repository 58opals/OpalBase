import Foundation

enum CashTokensCashAddrFixtureStore {
    static let vectors: [CashTokensCashAddrFixture] = [
        CashTokensCashAddrFixture(
            cashaddr: "bitcoincash:qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a",
            payload: "0000000000000000000000000000000000000000",
            type: 0
        ),
        CashTokensCashAddrFixture(
            cashaddr: "bitcoincash:zpm2qsznhks23z7629mms6s4cwef74vcwvrqekrq9w",
            payload: "0000000000000000000000000000000000000000",
            type: 2
        )
    ]
}

struct CashTokensCashAddrFixture: Codable {
    let cashaddr: String
    let payload: String
    let type: Int
}
