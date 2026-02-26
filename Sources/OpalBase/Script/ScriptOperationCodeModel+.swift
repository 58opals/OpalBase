// ScriptOperationCodeModel+Data.swift

import Foundation

extension ScriptOperationCodeModel {
    var data: Data { Data([self.rawValue]) }
}
