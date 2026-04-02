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

// MARK: - Property address helper

func addr(
    _ sel: AudioObjectPropertySelector,
    _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
    _ elem: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: sel, mScope: scope, mElement: elem)
}

// MARK: - Scalar get / set

func getScalar<T>(_ objectID: AudioObjectID, _ a: AudioObjectPropertyAddress) throws -> T {
    var a = a
    var size = UInt32(MemoryLayout<T>.size)
    let buf = UnsafeMutablePointer<T>.allocate(capacity: 1)
    defer { buf.deallocate() }
    let st = AudioObjectGetPropertyData(objectID, &a, 0, nil, &size, buf)
    guard st == noErr else { throw HALError(code: st) }
    return buf.pointee
}

func setScalar<T>(_ objectID: AudioObjectID, _ a: AudioObjectPropertyAddress, _ value: T) throws {
    var a = a
    var v = value
    let st = AudioObjectSetPropertyData(objectID, &a, 0, nil, UInt32(MemoryLayout<T>.size), &v)
    guard st == noErr else { throw HALError(code: st) }
}

// MARK: - CFString

func getCFString(_ objectID: AudioObjectID, _ a: AudioObjectPropertyAddress) throws -> String {
    var a = a
    var ref: Unmanaged<CFString>? = nil
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    let st = withUnsafeMutablePointer(to: &ref) {
        AudioObjectGetPropertyData(objectID, &a, 0, nil, &size, UnsafeMutableRawPointer($0))
    }
    guard st == noErr, let r = ref else { throw HALError(code: st == noErr ? -50 : st) }
    return r.takeRetainedValue() as String
}

// MARK: - Object ID array

func getObjectIDs(_ objectID: AudioObjectID, _ a: AudioObjectPropertyAddress) throws -> [AudioObjectID] {
    var a = a
    var size: UInt32 = 0
    var st = AudioObjectGetPropertyDataSize(objectID, &a, 0, nil, &size)
    guard st == noErr, size > 0 else { return [] }
    let count = Int(size) / MemoryLayout<AudioObjectID>.size
    let buf = UnsafeMutablePointer<AudioObjectID>.allocate(capacity: count)
    defer { buf.deallocate() }
    st = AudioObjectGetPropertyData(objectID, &a, 0, nil, &size, buf)
    guard st == noErr else { throw HALError(code: st) }
    return Array(UnsafeBufferPointer(start: buf, count: count))
}

// MARK: - Channel count

func getChannelCount(_ deviceID: AudioObjectID, scope: AudioObjectPropertyScope) -> Int {
    var a = addr(kAudioDevicePropertyStreamConfiguration, scope)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(deviceID, &a, 0, nil, &size) == noErr, size > 0 else { return 0 }
    let mem = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: 4)
    defer { mem.deallocate() }
    guard AudioObjectGetPropertyData(deviceID, &a, 0, nil, &size, mem) == noErr else { return 0 }
    let list = mem.assumingMemoryBound(to: AudioBufferList.self)
    let n = Int(list.pointee.mNumberBuffers)
    return withUnsafePointer(to: &list.pointee.mBuffers) { first in
        (0..<n).reduce(0) { $0 + Int(first.advanced(by: $1).pointee.mNumberChannels) }
    }
}

// MARK: - Control lookup

// kAudioControlPropertyScope = 'cscp'
private let kAudioControlPropertyScopeSelector: AudioObjectPropertySelector = 0x63736370

func findControl(
    ofClass classID: AudioClassID,
    under deviceID: AudioObjectID,
    scope: AudioObjectPropertyScope
) throws -> AudioObjectID? {
    let owned = try getObjectIDs(deviceID, addr(kAudioObjectPropertyOwnedObjects))

    let candidates = owned.filter { id in
        (try? getScalar(id, addr(kAudioObjectPropertyClass)) as AudioClassID) == classID
    }

    guard !candidates.isEmpty else { return nil }
    guard candidates.count > 1 else { return candidates[0] }

    // Multiple controls (e.g. input + output volume): pick by scope.
    return candidates.first {
        (try? getScalar($0, addr(kAudioControlPropertyScopeSelector)) as AudioObjectPropertyScope) == scope
    } ?? candidates.first
}

// MARK: - Device helpers

func getAllDeviceIDs() throws -> [AudioObjectID] {
    try getObjectIDs(AudioObjectID(kAudioObjectSystemObject), addr(kAudioHardwarePropertyDevices))
}

func deviceName(_ id: AudioObjectID) -> String {
    (try? getCFString(id, addr(kAudioObjectPropertyName))) ?? "Unknown (\(id))"
}

func deviceUID(_ id: AudioObjectID) -> String {
    (try? getCFString(id, addr(kAudioDevicePropertyDeviceUID))) ?? ""
}

func getSampleRate(_ id: AudioObjectID) -> Double? {
    try? getScalar(id, addr(kAudioDevicePropertyNominalSampleRate))
}

func findDevice(matching input: String) throws -> AudioObjectID {
    let devices = try getAllDeviceIDs()

    // Exact UID match.
    if let match = devices.first(where: { deviceUID($0) == input }) { return match }

    // Numeric object ID.
    if let n = AudioObjectID(input), devices.contains(n) { return n }

    // Case-insensitive name substring.
    let hits = devices.filter { deviceName($0).localizedCaseInsensitiveContains(input) }
    switch hits.count {
    case 0: throw AudioCtrlError.deviceNotFound(input)
    case 1: return hits[0]
    default:
        let names = hits.map { "\(deviceName($0)) (id:\($0))" }.joined(separator: ", ")
        throw AudioCtrlError.ambiguousDevice(input, names)
    }
}

// MARK: - Formatting helpers

func transportTypeName(_ t: UInt32) -> String {
    switch t {
    case kAudioDeviceTransportTypeBuiltIn:     return "Built-in"
    case kAudioDeviceTransportTypeAggregate:   return "Aggregate"
    case kAudioDeviceTransportTypeVirtual:     return "Virtual"
    case kAudioDeviceTransportTypePCI:         return "PCI"
    case kAudioDeviceTransportTypeUSB:         return "USB"
    case kAudioDeviceTransportTypeFireWire:    return "FireWire"
    case kAudioDeviceTransportTypeBluetooth:   return "Bluetooth"
    case kAudioDeviceTransportTypeBluetoothLE: return "Bluetooth LE"
    case kAudioDeviceTransportTypeHDMI:        return "HDMI"
    case kAudioDeviceTransportTypeDisplayPort: return "DisplayPort"
    case kAudioDeviceTransportTypeAirPlay:     return "AirPlay"
    case kAudioDeviceTransportTypeAVB:         return "AVB"
    case kAudioDeviceTransportTypeThunderbolt: return "Thunderbolt"
    default: return String(format: "0x%08X", t)
    }
}

/// Pretty-print a UInt32 as a FourCC if all bytes are printable ASCII.
func fourCC(_ v: UInt32) -> String {
    let b: [UInt8] = [
        UInt8((v >> 24) & 0xFF), UInt8((v >> 16) & 0xFF),
        UInt8((v >>  8) & 0xFF), UInt8( v        & 0xFF),
    ]
    return b.allSatisfy({ $0 > 31 && $0 < 127 })
        ? "'\(String(bytes: b, encoding: .ascii)!)'"
        : String(format: "0x%08X", v)
}

/// Parse a selector from a 4-char code (e.g. "msrt"), hex ("0x6D737274"), or decimal.
func parseSelector(_ s: String) -> AudioObjectPropertySelector? {
    if s.hasPrefix("0x") || s.hasPrefix("0X") { return UInt32(s.dropFirst(2), radix: 16) }
    if let n = UInt32(s) { return n }
    let u = Array(s.unicodeScalars)
    guard u.count == 4 else { return nil }
    return u.reduce(0) { ($0 << 8) | $1.value }
}
