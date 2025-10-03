import Foundation
import Testing
@testable import OpalBase

@Suite("Key Pair to Cash Address", .tags(.unit, .key, .address, .crypto))
struct KeyPrivateKeyPublicKeyAddressSuite {
    @Test("derives expected keys, hashes, and addresses from known WIFs", .tags(.unit, .key, .address, .crypto))
    func derivesExpectedValuesFromKnownWIFs() throws {
        let vectors: [(wif: String, privateKey: String, publicKey: String, publicKeyHash: String, legacyAddress: String, cashAddress: String)] = [
            (
                wif: "L3uV4ompYyuMTg2YyLJpfaAqa4oHNq6x3Wa4iK1CkyxwyuEiYXXu",
                privateKey: "c77c4c76f2edf9b105c99cd0cdc9866b2889f5351a1da2452220105df774d5f2",
                publicKey:  "034c571b087c1294a502870d5b3af90279365e8faed9dfce06b0d5b0e1177659b3",
                publicKeyHash: "4e7df7a4f7acfe23c6f593028a048a867a862b7f",
                legacyAddress: "18A2cL3ukWFnSCMMSKPpDSKb3Uwq8PusV9",
                cashAddress: "bitcoincash:qp88maay77k0ug7x7kfs9zsy32r84p3t0un4ca44u9"
            ),
            (
                wif: "L3vQMw6CafWtrrfMTVCqVRNnK9CWhz5c2nX7X4pqkx5WRat6ScNC",
                privateKey: "c7f54fe8621ede6a8c14159ded0eeafc132b2e3cfe66916beb6c00ab66d697a5",
                publicKey:  "0281d544137c9abfec10e60cc75c4cd08cdcb796e03e2e1e2d5e47aeff40e52f6b",
                publicKeyHash: "4e22f7d2617323d696130dbe8ab44727042d15b5",
                legacyAddress: "1889bayUGobyGkKCM6i8DaoTAj88ronGmw",
                cashAddress: "bitcoincash:qp8z9a7jv9ej845kzvxmaz45gunsgtg4k5646q64zv"
            ),
            (
                wif: "KwLGkssAYAhJppbEndr8PUnnK2qGFppdxbtyy164cfEXQ43f4xq2",
                privateKey: "03602311f498bb59ad13dd4e6d5e14cdf301c03ac205d1f982245a029230ef50",
                publicKey:  "03d00c07198ffedcc19d7b18fbe56407f3e46b1a4216d389b7def473de2e317e2e",
                publicKeyHash: "31e5e2e2c9e8965d422704a10f3cfebfe03f03ff",
                legacyAddress: "15YqWBKfTbAVGf7yHDzjnLokwUzyoby3M2",
                cashAddress: "bitcoincash:qqc7tchze85fvh2zyuz2zreul6l7q0crlun2s6uj9a"
            ),
            (
                wif: "L2KYK25VwuS8cpk7Vx9wDb3EPnDKJzq7gQgx3T5BacSsqa5ZpkEq",
                privateKey: "982fa04cfb2376b13f6b29246b95af1c705c86e109594c2b188e8b6d454ec62a",
                publicKey:  "02e3f7c11fc329486c69373fe7d067da098bfd989e3946e4598a52a4d143a5f19e",
                publicKeyHash: "70d00d41e96cc76dd29a367ad1da21af57a1c883",
                legacyAddress: "1BHVvBF4DRiKu6cZmUsRXKd7ZvAbNMhXuK",
                cashAddress: "bitcoincash:qpcdqr2pa9kvwmwjngm845w6yxh40gwgsv8l5wu2vq"
            ),
            (
                wif: "L1ThoPAvF4M5sxfsZefWhv5V2vQDPtHVVRKkUKHshYQTQtFWqzrN",
                privateKey: "7e8c5e0e93516c23183cfd6c3b3b28208baf7b76d97b841adc255aa4d7ad97b0",
                publicKey:  "03f70f009186e17585a97b45ab9fc44d5985e005ca5dedcd327dc30aed53263e07",
                publicKeyHash: "ca013ddf48587e511d7ffa78865395efe68792fb",
                legacyAddress: "1KR6z2NvYodJXDDhW1dTh1BVU427L3yDDX",
                cashAddress: "bitcoincash:qr9qz0wlfpv8u5ga0la83pjnjhh7dpujlvj9xulvp2"
            )
        ]
        
        for vector in vectors {
            let privateKey = try PrivateKey(wif: vector.wif)
            #expect(privateKey.wif == vector.wif)
            #expect(privateKey.rawData.hexadecimalString == vector.privateKey)
            
            let publicKey = try PublicKey(privateKey: privateKey)
            #expect(publicKey.compressedData.hexadecimalString == vector.publicKey)
            
            let hash = PublicKey.Hash(publicKey: publicKey)
            #expect(hash.data.hexadecimalString == vector.publicKeyHash)
            
            let script = Script.p2pkh_OPCHECKSIG(hash: hash)
            let address = try Address(script: script)
            #expect(address.string == vector.cashAddress)
            #expect(address.lockingScript == script)
            
            let legacy = try Address.Legacy(script)
            #expect(legacy.string == vector.legacyAddress)
        }
    }
}
