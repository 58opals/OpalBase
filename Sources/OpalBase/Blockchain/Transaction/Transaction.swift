// Opal Base by 58 Opals

import Foundation

struct Transaction {
    let version: UInt32
    let inputs: Array<Input>
    let outputs: Array<Output>
    let locktime: UInt32
    
    var numberOfInputs: VLInt { .init(inputs.count) }
    var numberOfOutputs: VLInt { .init(outputs.count) }
    
    init(version: UInt32 = 2,
         inputs: Array<Input>,
         outputs: Array<Output>,
         locktime: UInt32 = 0) {
        self.version = version
        self.inputs = inputs
        self.outputs = outputs
        self.locktime = locktime
    }
}
