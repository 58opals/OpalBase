// OpalBaseDiagnosticsPresentation.swift

import Foundation
@preconcurrency import OpalDiagnostics

enum OpalBaseDiagnosticsPresentation {
    static func fields(
        for error: Swift.Error,
        errorCode: OpalDiagnostics.ErrorCode
    ) -> [OpalDiagnostics.Field] {
        var fields: [OpalDiagnostics.Field] = [
            .errorCode(errorCode),
            .errorType(error),
            .errorMessage(message(for: error))
        ]

        if let networkError = error as? OpalBase.Network.Error {
            fields += networkFields(for: networkError)
        }

        return fields
    }

    private static func message(for error: Swift.Error) -> String {
        if let networkError = error as? OpalBase.Network.Error {
            return networkError.description
        }

        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription,
           let message = makeDiagnosticErrorMessage(description) {
            return message
        }

        return makeDiagnosticErrorMessage(String(describing: error)) ?? "Unknown error"
    }

    private static func makeDiagnosticErrorMessage(_ message: String) -> String? {
        let singleLineMessage = makeSingleLineText(message)

        return singleLineMessage.isEmpty ? nil : singleLineMessage
    }

    private static func networkFields(
        for error: OpalBase.Network.Error
    ) -> [OpalDiagnostics.Field] {
        var fields: [OpalDiagnostics.Field] = [
            .publicValue(OpalDiagnostics.Field.Name.errorReason, error.reason.description)
        ]

        if case .server(let code) = error.reason {
            fields.append(.publicValue(OpalDiagnostics.Field.Name.serverCode, code))
        }

        for item in error.publicDiagnosticMetadata {
            guard let fieldName = makePublicNetworkMetadataFieldName(for: item.name) else { continue }
            fields.append(.publicValue(fieldName, item.value))
        }

        for item in error.privateDiagnosticMetadata {
            fields.append(.privateValue(
                OpalDiagnostics.Field.Name.privateErrorMetadata,
                makePrivateNetworkMetadataValue(for: item)
            ))
        }

        return fields
    }

    private static func makePrivateNetworkMetadataValue(
        for item: (name: String, value: String)
    ) -> String {
        let name = makeSingleLineText(item.name)
        let fallbackName = name.isEmpty ? "metadata" : name

        return "\(fallbackName)=\(makeSingleLineText(item.value))"
    }

    private static func makeSingleLineText(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    private static func makePublicNetworkMetadataFieldName(for name: String) -> String? {
        switch name {
        case OpalBase.Network.Error.DiagnosticMetadataKey.closeCode:
            return OpalDiagnostics.Field.Name.closeCode
        case OpalBase.Network.Error.DiagnosticMetadataKey.timeoutSeconds:
            return OpalDiagnostics.Field.Name.timeoutSeconds
        case OpalBase.Network.Error.DiagnosticMetadataKey.minimumVersion:
            return OpalDiagnostics.Field.Name.minimumVersion
        case OpalBase.Network.Error.DiagnosticMetadataKey.maximumVersion:
            return OpalDiagnostics.Field.Name.maximumVersion
        default:
            return nil
        }
    }
}
