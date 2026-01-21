import Foundation

enum BitcoinImprovementProposalSchnorrTestVectors {
    struct Vector: Sendable {
        let index: Int
        let secretKeyHexadecimal: String?
        let publicKeyHexadecimal: String
        let messageHexadecimal: String
        let signatureHexadecimal: String
        let expectedVerificationResult: Bool
        let comment: String?
    }
    
    static let all: [Vector] = [
        .init(
            index: 1,
            secretKeyHexadecimal: "0000000000000000000000000000000000000000000000000000000000000001",
            publicKeyHexadecimal: "0279BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798",
            messageHexadecimal: "0000000000000000000000000000000000000000000000000000000000000000",
            signatureHexadecimal: "787A848E71043D280C50470E8E1532B2DD5D20EE912A45DBDD2BD1DFBF187EF67031A98831859DC34DFFEEDDA86831842CCD0079E1F92AF177F7F22CC1DCED05",
            expectedVerificationResult: true,
            comment: nil
        ),
        .init(
            index: 2,
            secretKeyHexadecimal: "B7E151628AED2A6ABF7158809CF4F3C762E7160F38B4DA56A784D9045190CFEF",
            publicKeyHexadecimal: "02DFF1D77F2A671C5F36183726DB2341BE58FEAE1DA2DECED843240F7B502BA659",
            messageHexadecimal: "243F6A8885A308D313198A2E03707344A4093822299F31D0082EFA98EC4E6C89",
            signatureHexadecimal: "2A298DACAE57395A15D0795DDBFD1DCB564DA82B0F269BC70A74F8220429BA1D1E51A22CCEC35599B8F266912281F8365FFC2D035A230434A1A64DC59F7013FD",
            expectedVerificationResult: true,
            comment: nil
        ),
        .init(
            index: 3,
            secretKeyHexadecimal: "C90FDAA22168C234C4C6628B80DC1CD129024E088A67CC74020BBEA63B14E5C7",
            publicKeyHexadecimal: "03FAC2114C2FBB091527EB7C64ECB11F8021CB45E8E7809D3C0938E4B8C0E5F84B",
            messageHexadecimal: "5E2D58D8B3BCDF1ABADEC7829054F90DDA9805AAB56C77333024B9D0A508B75C",
            signatureHexadecimal: "00DA9B08172A9B6F0466A2DEFD817F2D7AB437E0D253CB5395A963866B3574BE00880371D01766935B92D2AB4CD5C8A2A5837EC57FED7660773A05F0DE142380",
            expectedVerificationResult: true,
            comment: nil
        ),
        .init(
            index: 4,
            secretKeyHexadecimal: nil,
            publicKeyHexadecimal: "03DEFDEA4CDB677750A420FEE807EACF21EB9898AE79B9768766E4FAA04A2D4A34",
            messageHexadecimal: "4DF3C3F68FCC83B27E9D42C90431A72499F17875C81A599B566C9889B9696703",
            signatureHexadecimal: "00000000000000000000003B78CE563F89A0ED9414F5AA28AD0D96D6795F9C6302A8DC32E64E86A333F20EF56EAC9BA30B7246D6D25E22ADB8C6BE1AEB08D49D",
            expectedVerificationResult: true,
            comment: nil
        ),
        .init(
            index: 5,
            secretKeyHexadecimal: nil,
            publicKeyHexadecimal: "031B84C5567B126440995D3ED5AABA0565D71E1834604819FF9C17F5E9D5DD078F",
            messageHexadecimal: "0000000000000000000000000000000000000000000000000000000000000000",
            signatureHexadecimal: "52818579ACA59767E3291D91B76B637BEF062083284992F2D95F564CA6CB4E3530B1DA849C8E8304ADC0CFE870660334B3CFC18E825EF1DB34CFAE3DFC5D8187",
            expectedVerificationResult: true,
            comment: "test fails if jacobi symbol of x(R) instead of y(R) is used"
        ),
        .init(
            index: 6,
            secretKeyHexadecimal: nil,
            publicKeyHexadecimal: "03FAC2114C2FBB091527EB7C64ECB11F8021CB45E8E7809D3C0938E4B8C0E5F84B",
            messageHexadecimal: "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF",
            signatureHexadecimal: "570DD4CA83D4E6317B8EE6BAE83467A1BF419D0767122DE409394414B05080DCE9EE5F237CBD108EABAE1E37759AE47F8E4203DA3532EB28DB860F33D62D49BD",
            expectedVerificationResult: true,
            comment: "test fails if msg is reduced modulo p or n"
        ),
        .init(
            index: 7,
            secretKeyHexadecimal: nil,
            publicKeyHexadecimal: "03EEFDEA4CDB677750A420FEE807EACF21EB9898AE79B9768766E4FAA04A2D4A34",
            messageHexadecimal: "4DF3C3F68FCC83B27E9D42C90431A72499F17875C81A599B566C9889B9696703",
            signatureHexadecimal: "00000000000000000000003B78CE563F89A0ED9414F5AA28AD0D96D6795F9C6302A8DC32E64E86A333F20EF56EAC9BA30B7246D6D25E22ADB8C6BE1AEB08D49D",
            expectedVerificationResult: false,
            comment: "public key not on the curve"
        ),
        .init(
            index: 8,
            secretKeyHexadecimal: nil,
            publicKeyHexadecimal: "02DFF1D77F2A671C5F36183726DB2341BE58FEAE1DA2DECED843240F7B502BA659",
            messageHexadecimal: "243F6A8885A308D313198A2E03707344A4093822299F31D0082EFA98EC4E6C89",
            signatureHexadecimal: "2A298DACAE57395A15D0795DDBFD1DCB564DA82B0F269BC70A74F8220429BA1DFA16AEE06609280A19B67A24E1977E4697712B5FD2943914ECD5F730901B4AB7",
            expectedVerificationResult: false,
            comment: "incorrect R residuosity"
        ),
        .init(
            index: 9,
            secretKeyHexadecimal: nil,
            publicKeyHexadecimal: "03FAC2114C2FBB091527EB7C64ECB11F8021CB45E8E7809D3C0938E4B8C0E5F84B",
            messageHexadecimal: "5E2D58D8B3BCDF1ABADEC7829054F90DDA9805AAB56C77333024B9D0A508B75C",
            signatureHexadecimal: "00DA9B08172A9B6F0466A2DEFD817F2D7AB437E0D253CB5395A963866B3574BED092F9D860F1776A1F7412AD8A1EB50DACCC222BC8C0E26B2056DF2F273EFDEC",
            expectedVerificationResult: false,
            comment: "negated message"
        ),
        .init(
            index: 10,
            secretKeyHexadecimal: nil,
            publicKeyHexadecimal: "0279BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798",
            messageHexadecimal: "0000000000000000000000000000000000000000000000000000000000000000",
            signatureHexadecimal: "787A848E71043D280C50470E8E1532B2DD5D20EE912A45DBDD2BD1DFBF187EF68FCE5677CE7A623CB20011225797CE7A8DE1DC6CCD4F754A47DA6C600E59543C",
            expectedVerificationResult: false,
            comment: "negated s value"
        ),
        .init(
            index: 11,
            secretKeyHexadecimal: nil,
            publicKeyHexadecimal: "03DFF1D77F2A671C5F36183726DB2341BE58FEAE1DA2DECED843240F7B502BA659",
            messageHexadecimal: "243F6A8885A308D313198A2E03707344A4093822299F31D0082EFA98EC4E6C89",
            signatureHexadecimal: "2A298DACAE57395A15D0795DDBFD1DCB564DA82B0F269BC70A74F8220429BA1D1E51A22CCEC35599B8F266912281F8365FFC2D035A230434A1A64DC59F7013FD",
            expectedVerificationResult: false,
            comment: "negated public key"
        ),
        .init(
            index: 12,
            secretKeyHexadecimal: nil,
            publicKeyHexadecimal: "02DFF1D77F2A671C5F36183726DB2341BE58FEAE1DA2DECED843240F7B502BA659",
            messageHexadecimal: "243F6A8885A308D313198A2E03707344A4093822299F31D0082EFA98EC4E6C89",
            signatureHexadecimal: "00000000000000000000000000000000000000000000000000000000000000009E9D01AF988B5CEDCE47221BFA9B222721F3FA408915444A4B489021DB55775F",
            expectedVerificationResult: false,
            comment: "sG - eP is infinite.\nTest fails in single verification if jacobi(y(inf)) is defined as 1 and x(inf) as 0"
        ),
        .init(
            index: 13,
            secretKeyHexadecimal: nil,
            publicKeyHexadecimal: "02DFF1D77F2A671C5F36183726DB2341BE58FEAE1DA2DECED843240F7B502BA659",
            messageHexadecimal: "243F6A8885A308D313198A2E03707344A4093822299F31D0082EFA98EC4E6C89",
            signatureHexadecimal: "0000000000000000000000000000000000000000000000000000000000000001D37DDF0254351836D84B1BD6A795FD5D523048F298C4214D187FE4892947F728",
            expectedVerificationResult: false,
            comment: "sG - eP is infinite.\nTest fails in single verification if jacobi(y(inf)) is defined as 1 and x(inf) as 1"
        ),
        .init(
            index: 14,
            secretKeyHexadecimal: nil,
            publicKeyHexadecimal: "02DFF1D77F2A671C5F36183726DB2341BE58FEAE1DA2DECED843240F7B502BA659",
            messageHexadecimal: "243F6A8885A308D313198A2E03707344A4093822299F31D0082EFA98EC4E6C89",
            signatureHexadecimal: "4A298DACAE57395A15D0795DDBFD1DCB564DA82B0F269BC70A74F8220429BA1D1E51A22CCEC35599B8F266912281F8365FFC2D035A230434A1A64DC59F7013FD",
            expectedVerificationResult: false,
            comment: "sig[0:32] is not an X coordinate on the curve"
        ),
        .init(
            index: 15,
            secretKeyHexadecimal: nil,
            publicKeyHexadecimal: "02DFF1D77F2A671C5F36183726DB2341BE58FEAE1DA2DECED843240F7B502BA659",
            messageHexadecimal: "243F6A8885A308D313198A2E03707344A4093822299F31D0082EFA98EC4E6C89",
            signatureHexadecimal: "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFC2F1E51A22CCEC35599B8F266912281F8365FFC2D035A230434A1A64DC59F7013FD",
            expectedVerificationResult: false,
            comment: "sig[0:32] is equal to field size"
        ),
        .init(
            index: 16,
            secretKeyHexadecimal: nil,
            publicKeyHexadecimal: "02DFF1D77F2A671C5F36183726DB2341BE58FEAE1DA2DECED843240F7B502BA659",
            messageHexadecimal: "243F6A8885A308D313198A2E03707344A4093822299F31D0082EFA98EC4E6C89",
            signatureHexadecimal: "2A298DACAE57395A15D0795DDBFD1DCB564DA82B0F269BC70A74F8220429BA1DFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141",
            expectedVerificationResult: false,
            comment: "sig[32:64] is equal to curve order"
        ),
    ]
}
