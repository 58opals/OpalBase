// OpalDiagnostics+Field+OpalBase.swift

@preconcurrency public import OpalDiagnostics

public extension OpalDiagnostics.Field {
    enum Name {
        public static let operation = "operation"
        public static let module = "module"
        public static let accountIndex = "account_index"
        public static let accountCount = "account_count"
        public static let usage = "usage"
        public static let network = "network"
        public static let outcome = "outcome"
        public static let status = "status"
        public static let recipientCount = "recipient_count"
        public static let inputCount = "input_count"
        public static let outputCount = "output_count"
        public static let utxoCount = "utxo_count"
        public static let addressCount = "address_count"
        public static let transactionCount = "transaction_count"
        public static let tokenCategoryCount = "token_category_count"
        public static let tokenMetadataCount = "token_metadata_count"
        public static let includeUnconfirmed = "include_unconfirmed"
        public static let byteCount = "byte_count"
        public static let confirmationCount = "confirmation_count"
        public static let roundTraceID = "round_trace_id"
        public static let baseTraceID = "base_trace_id"
        public static let reconnectionAttemptCount = "reconnection_attempt_count"
        public static let reconnectSuccessCount = "reconnect_success_count"
        public static let inflightUnaryCallCount = "inflight_unary_call_count"
        public static let activeSubscriptionCount = "active_subscription_count"
        public static let errorCode = "error_code"
        public static let errorType = "error_type"
        public static let errorMessage = "error_message"

        public static let all: [String] = [
            operation, module, accountIndex, accountCount, usage, network, outcome, status,
            recipientCount, inputCount, outputCount, utxoCount, addressCount,
            transactionCount, tokenCategoryCount, tokenMetadataCount, includeUnconfirmed,
            byteCount, confirmationCount, roundTraceID, baseTraceID,
            reconnectionAttemptCount, reconnectSuccessCount,
            inflightUnaryCallCount, activeSubscriptionCount,
            errorCode, errorType, errorMessage
        ]
    }

    static func publicValue(_ name: String, _ value: String) -> Self {
        Self(name: name, publicValue: value)
    }

    static func publicValue(_ name: String, _ value: Int) -> Self {
        Self(name: name, value: value)
    }

    static func publicValue(_ name: String, _ value: UInt64) -> Self {
        Self(name: name, value: value)
    }

    static func publicValue(_ name: String, _ value: Bool) -> Self {
        Self(name: name, value: value)
    }

    static func privateValue(_ name: String, _ value: String) -> Self {
        Self(name: name, value: value, privacy: .private)
    }

    static func operation(_ operation: String) -> Self {
        publicValue(Name.operation, operation)
    }

    static func module(_ module: String = "opalbase") -> Self {
        publicValue(Name.module, module)
    }

    static func accountIndex(_ index: UInt32) -> Self {
        publicValue(Name.accountIndex, UInt64(index))
    }

    static func usage(_ usage: OpalBase.Key.DerivationPath.Usage) -> Self {
        publicValue(Name.usage, diagnosticsName(for: usage))
    }

    static func network(_ network: OpalBase.Network.Environment) -> Self {
        publicValue(Name.network, diagnosticsName(for: network))
    }

    static func errorFields(
        for error: Swift.Error,
        fallback: OpalDiagnostics.ErrorCode = .unknown
    ) -> [Self] {
        [
            .errorCode(.opalBaseCode(for: error, fallback: fallback)),
            .errorType(error),
            .errorMessage(String(describing: error))
        ]
    }

    static func errorFields(
        for error: Swift.Error,
        errorCode: OpalDiagnostics.ErrorCode
    ) -> [Self] {
        [
            .errorCode(errorCode),
            .errorType(error),
            .errorMessage(String(describing: error))
        ]
    }

    private static func diagnosticsName(
        for usage: OpalBase.Key.DerivationPath.Usage
    ) -> String {
        switch usage {
        case .receiving:
            return "receiving"
        case .change:
            return "change"
        }
    }

    private static func diagnosticsName(
        for network: OpalBase.Network.Environment
    ) -> String {
        switch network {
        case .mainnet:
            return "mainnet"
        case .chipnet:
            return "chipnet"
        case .testnet:
            return "testnet"
        }
    }
}
