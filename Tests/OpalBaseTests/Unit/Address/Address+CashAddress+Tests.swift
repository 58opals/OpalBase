import Testing
@testable import OpalBase

@Suite("Cashaddr Sanitiser", .tags(.unit, .address))
struct AddressCashaddrSanitiserSuite {
    private let payload = "qp3wjpa3tjlj042z7x0d3xd309ux8etdc3h0n0l0q0"
    
    @Test("returns lowercase cashaddr payload unchanged")
    func filterBase32KeepsLowercaseCashaddrPayload() {
        let lowercase = "bitcoincash:\(payload)"
        
        #expect(Address.filterBase32(from: lowercase) == payload)
    }
    
    @Test("returns uppercase cashaddr payload unchanged")
    func filterBase32KeepsUppercaseCashaddrPayload() {
        let uppercase = "bitcoincash:\(payload)".uppercased()
        let uppercasePayload = payload.uppercased()
        
        #expect(Address.filterBase32(from: uppercase) == uppercasePayload)
    }
}
