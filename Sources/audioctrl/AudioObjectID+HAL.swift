import ArgumentParser
import CoreAudio

// MARK: - Property address

extension AudioObjectID {
    static var allDeviceIDs: [AudioObjectID] {
        get throws(HALError) {
            try AudioObjectID(kAudioObjectSystemObject).getObjectIDs(addr(kAudioHardwarePropertyDevices))
        }
    }
    
    static func findDevice(matching input: String, allowNumericID: Bool = true) throws -> AudioObjectID {
        let devices = try allDeviceIDs
        if let match = devices.first(where: { $0.deviceUID == input }) { return match }
        if allowNumericID, let n = AudioObjectID(input), devices.contains(n) { return n }
        let hits = devices.filter { $0.deviceName.localizedCaseInsensitiveContains(input) }
        switch hits.count {
        case 0: throw AudioCtrlError.deviceNotFound(input)
        case 1: return hits[0]
        default:
            let names = hits.map { "\($0.deviceName) (id:\($0))" }.joined(separator: ", ")
            throw AudioCtrlError.ambiguousDevice(input, names)
        }
    }

    static func findDeviceByName(_ input: String) throws -> AudioObjectID {
        try findDevice(matching: input, allowNumericID: false)
    }

    static func findDeviceByID(_ id: AudioObjectID) throws -> AudioObjectID {
        let devices = try allDeviceIDs
        guard devices.contains(id) else { throw AudioCtrlError.deviceNotFound(String(id)) }
        return id
    }

    static func resolve(name: String?, id: UInt32?) throws -> AudioObjectID {
        switch (name, id) {
        case (let n?, nil): return try findDeviceByName(n)
        case (nil, let i?): return try findDeviceByID(AudioObjectID(i))
        case (nil, nil):    preconditionFailure("Called without a flag set")
        default:            throw ValidationError("Use only one of --name or --id.")
        }
    }
    
    var deviceName: String {
        (try? getString(addr(kAudioObjectPropertyName))) ?? "Unknown (\(self))"
    }
    
    var deviceUID: String {
        (try? getString(addr(kAudioDevicePropertyDeviceUID))) ?? ""
    }
    
    var sampleRate: Double? {
        try? getScalarProperty(kAudioDevicePropertyNominalSampleRate)
    }
    
    func getScalarProperty<T: Numeric>(
        _ selector: AudioObjectPropertySelector,
        _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        _ elem: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) throws(HALError) -> T {
        try getScalarProperty(addr(selector, scope, elem))
    }
    
    func getScalarProperty<T: Numeric>(_ a: AudioObjectPropertyAddress) throws(HALError) -> T {
        var a = a
        var size = UInt32(MemoryLayout<T>.size)
        let buf = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { buf.deallocate() }
        let st = AudioObjectGetPropertyData(self, &a, 0, nil, &size, buf)
        guard st == noErr else { throw HALError(code: st) }
        return buf.pointee
    }
    
    func setScalarProperty<T: Numeric>(_ a: AudioObjectPropertyAddress, _ value: T) throws(HALError) {
        var a = a
        var v = value
        let st = withUnsafeBytes(of: &v) { buf in
            AudioObjectSetPropertyData(self, &a, 0, nil, UInt32(buf.count), buf.baseAddress!)
        }
        guard st == noErr else { throw HALError(code: st) }
    }
    
    func getString(_ a: AudioObjectPropertyAddress) throws(HALError) -> String {
        var a = a
        var ref: Unmanaged<CFString>? = nil
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let st = withUnsafeMutablePointer(to: &ref) {
            AudioObjectGetPropertyData(self, &a, 0, nil, &size, UnsafeMutableRawPointer($0))
        }
        guard st == noErr, let r = ref else { throw HALError(code: st == noErr ? -50 : st) }
        return r.takeRetainedValue() as String
    }

    func readValue(type: PropType, from a: AudioObjectPropertyAddress) throws -> String {
        switch type {
        case .float32: return String(format: "%g", try getScalarProperty(a) as Float32)
        case .float64: return String(format: "%g", try getScalarProperty(a) as Float64)
        case .uint32:  return "\(try getScalarProperty(a) as UInt32)"
        case .string:  return try getString(a)
        }
    }

    func writeValue(_ s: String, type: PropType, to a: AudioObjectPropertyAddress) throws {
        switch type {
        case .float32:
            guard let v = Float32(s) else { throw AudioCtrlError.typeMismatch("expected Float32, got '\(s)'") }
            try setScalarProperty(a, v)
        case .float64:
            guard let v = Float64(s) else { throw AudioCtrlError.typeMismatch("expected Float64, got '\(s)'") }
            try setScalarProperty(a, v)
        case .uint32:
            guard let v = UInt32(s) else { throw AudioCtrlError.typeMismatch("expected UInt32, got '\(s)'") }
            try setScalarProperty(a, v)
        case .string:
            throw AudioCtrlError.notSettable("\(s) (string properties are not writable)")
        }
    }
    
    func getObjectIDs(_ a: AudioObjectPropertyAddress) throws(HALError) -> [AudioObjectID] {
        var a = a
        var size: UInt32 = 0
        var st = AudioObjectGetPropertyDataSize(self, &a, 0, nil, &size)
        guard st == noErr, size > 0 else { return [] }
        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        let buf = UnsafeMutablePointer<AudioObjectID>.allocate(capacity: count)
        defer { buf.deallocate() }
        st = AudioObjectGetPropertyData(self, &a, 0, nil, &size, buf)
        guard st == noErr else { throw HALError(code: st) }
        return Array(UnsafeBufferPointer(start: buf, count: count))
    }
    
    func getChannelCount(scope: AudioObjectPropertyScope) -> Int {
        var a = addr(kAudioDevicePropertyStreamConfiguration, scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(self, &a, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let mem = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: 4)
        defer { mem.deallocate() }
        guard AudioObjectGetPropertyData(self, &a, 0, nil, &size, mem) == noErr else { return 0 }
        let list = mem.assumingMemoryBound(to: AudioBufferList.self)
        let n = Int(list.pointee.mNumberBuffers)
        return withUnsafePointer(to: &list.pointee.mBuffers) { first in
            (0..<n).reduce(0) { $0 + Int(first.advanced(by: $1).pointee.mNumberChannels) }
        }
    }
    
    var controls: [ControlInfo] {
        get throws {
            try getObjectIDs(addr(kAudioObjectPropertyOwnedObjects))
                .compactMap { id in
                    guard let classID = try? id.getScalarProperty(kAudioObjectPropertyClass) as AudioClassID else { return nil }
                    // Detect controls by whether they respond to kAudioControlPropertyScopeSelector.
                    // Checking baseClass is unreliable because the hierarchy can be multiple levels deep.
                    var scopeAddr = addr(kAudioControlPropertyScopeSelector)
                    guard AudioObjectHasProperty(id, &scopeAddr) else { return nil }
                    let scope = (try? id.getScalarProperty(kAudioControlPropertyScopeSelector) as AudioObjectPropertyScope)?.value ?? "global"
                    return ControlInfo(objectID: id, classID: classID, className: classID.controlClassName, scope: scope)
                }
        }
    }
    
    func findControl(ofClass classID: AudioClassID, scope: AudioObjectPropertyScope) throws -> AudioObjectID? {
        let owned = try getObjectIDs(addr(kAudioObjectPropertyOwnedObjects))

        let candidates = owned.filter { id in
            (try? id.getScalarProperty(kAudioObjectPropertyClass) as AudioClassID) == classID
        }

        guard !candidates.isEmpty else { return nil }
        guard candidates.count > 1 else { return candidates[0] }

        // Multiple controls (e.g. input + output volume): pick by scope.
        return candidates.first {
            (try? $0.getScalarProperty(kAudioControlPropertyScopeSelector) as AudioObjectPropertyScope) == scope
        } ?? candidates.first
    }
    
    subscript(prop: KnownProp) -> String {
        get throws {
            // Transport type gets a human-readable name instead of the raw UInt32.
            if prop.selector == kAudioDevicePropertyTransportType {
                return transportTypeName(try getScalarProperty(prop.addr))
            }
            return try readValue(type: prop.type, from: prop.addr)
        }
    }

    func writeProp(_ prop: KnownProp, value: String) throws {
        try writeValue(value, type: prop.type, to: prop.addr)
    }

    func readRaw(sel: AudioObjectPropertySelector, scope: AudioObjectPropertyScope, elem: AudioObjectPropertyElement, type: PropType) throws -> String {
        try readValue(type: type, from: addr(sel, scope, elem))
    }

    func writeRaw(sel: AudioObjectPropertySelector, scope: AudioObjectPropertyScope, elem: AudioObjectPropertyElement, type: PropType, value: String) throws {
        try writeValue(value, type: type, to: addr(sel, scope, elem))
    }
}

extension AudioClassID {
    var controlClassName: String {
        switch self {
        case kAudioVolumeControlClassID:    return "volume"
        case kAudioMuteControlClassID:      return "mute"
        case kAudioStereoPanControlClassID: return "stereo-pan"
        case kAudioSoloControlClassID:      return "solo"
        case kAudioJackControlClassID:      return "jack"
        case kAudioLFEMuteControlClassID:   return "lfe-mute"
        case kAudioPhantomPowerControlClassID: return "phantom-power"
        case kAudioPhaseInvertControlClassID:  return "phase-invert"
        case kAudioClipLightControlClassID: return "clip-light"
        case kAudioListenbackControlClassID:   return "listenback"
        case kAudioClockSourceControlClassID:  return "clock-source"
        default: return fourCC(self)
        }
    }
}

extension AudioObjectPropertyScope {
    var value: String {
        switch self {
        case kAudioObjectPropertyScopeInput:  return "input"
        case kAudioObjectPropertyScopeOutput: return "output"
        default: return "global"
        }
    }
    
    static func from(_ s: String) throws(ValidationError) -> AudioObjectPropertyScope {
        switch s.lowercased() {
        case "global", "g": return kAudioObjectPropertyScopeGlobal
        case "input",  "i": return kAudioObjectPropertyScopeInput
        case "output", "o": return kAudioObjectPropertyScopeOutput
        default: throw ValidationError("Invalid scope '\(s)'. Use: global, input, output.")
        }
    }
}

func addr(
    _ selector: AudioObjectPropertySelector,
    _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
    _ elem: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: elem)
}

// MARK: - Transport type

func transportSortOrder(_ t: UInt32) -> Int {
    if #available(macOS 13.0, *) {
        switch t {
        case kAudioDeviceTransportTypeContinuityCaptureWired,
             kAudioDeviceTransportTypeContinuityCaptureWireless: return 1
        default: break
        }
    }
    switch t {
    case kAudioDeviceTransportTypeBuiltIn:     return 0
    case kAudioDeviceTransportTypeBluetooth,
         kAudioDeviceTransportTypeBluetoothLE: return 1
    case kAudioDeviceTransportTypeUSB:         return 2
    case kAudioDeviceTransportTypeHDMI,
         kAudioDeviceTransportTypeDisplayPort,
         kAudioDeviceTransportTypeThunderbolt: return 3
    case kAudioDeviceTransportTypeVirtual:     return 4
    case kAudioDeviceTransportTypeAggregate:   return 5
    default:                                   return 6
    }
}

func transportTypeName(_ t: UInt32) -> String {
    if #available(macOS 13.0, *) {
        switch t {
        case kAudioDeviceTransportTypeContinuityCaptureWired:    return "Continuity (Wired)"
        case kAudioDeviceTransportTypeContinuityCaptureWireless: return "Continuity (Wireless)"
        default: break
        }
    }
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
    return b.allSatisfy { $0 > 31 && $0 < 127 }
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

// MARK: - Spacing Formatters

func ljust(_ s: String, _ w: Int) -> String {
    s.count >= w ? String(s.prefix(w)) : s + String(repeating: " ", count: w - s.count)
}

func rjust(_ s: String, _ w: Int) -> String {
    s.count >= w ? s : String(repeating: " ", count: w - s.count) + s
}
