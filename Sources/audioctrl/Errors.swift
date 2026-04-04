import CoreAudio
import Foundation

// MARK: - Errors

struct HALError: Error, CustomStringConvertible {
    let code: OSStatus

    var description: String {
        let b: [UInt8] = [
            UInt8((code >> 24) & 0xFF), UInt8((code >> 16) & 0xFF),
            UInt8((code >>  8) & 0xFF), UInt8( code        & 0xFF),
        ]
        if b.allSatisfy({ $0 > 31 && $0 < 127 }) {
            return "CoreAudio error '\(String(bytes: b, encoding: .ascii)!)' (\(code))"
        }
        return "CoreAudio error \(code)"
    }
}

enum AudioCtrlError: Error, CustomStringConvertible {
    case deviceNotFound(String)
    case ambiguousDevice(String, String)
    case unknownProperty(String)
    case notSettable(String)
    case controlNotFound(String)
    case typeMismatch(String)

    var description: String {
        switch self {
        case .deviceNotFound(let d):         return "No device found matching '\(d)'."
        case .ambiguousDevice(let d, let m): return "'\(d)' is ambiguous: \(m)."
        case .unknownProperty(let p):        return "Unknown property '\(p)'. Pass --type to read it as a raw selector."
        case .notSettable(let p):            return "'\(p)' is read-only."
        case .controlNotFound(let c):        return "No \(c) control found on this device."
        case .typeMismatch(let m):           return "Type error: \(m)."
        }
    }
}
