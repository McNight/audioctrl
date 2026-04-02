import ArgumentParser
import CoreAudio
import Foundation

// MARK: - Property data type

enum PropType: String, CaseIterable, ExpressibleByArgument {
    case float32, float64, uint32, string

    init?(argument: String) {
        self.init(rawValue: argument.lowercased())
    }
}

// MARK: - Known property registry

enum PropTarget {
    case device
    case control(classID: AudioClassID, scope: AudioObjectPropertyScope)
}

struct KnownProp {
    let name: String
    let description: String
    let selector: AudioObjectPropertySelector
    let propScope: AudioObjectPropertyScope
    let element: AudioObjectPropertyElement
    let type: PropType
    let target: PropTarget
    let settable: Bool
}

let knownProps: [KnownProp] = [
    // ── Device-level ──────────────────────────────────────────────────────────
    KnownProp(name: "name",          description: "Device name",                selector: kAudioObjectPropertyName,              propScope: kAudioObjectPropertyScopeGlobal, element: kAudioObjectPropertyElementMain, type: .string,  target: .device, settable: false),
    KnownProp(name: "uid",           description: "Unique identifier (UID)",    selector: kAudioDevicePropertyDeviceUID,         propScope: kAudioObjectPropertyScopeGlobal, element: kAudioObjectPropertyElementMain, type: .string,  target: .device, settable: false),
    KnownProp(name: "model-uid",     description: "Model UID",                  selector: kAudioDevicePropertyModelUID,          propScope: kAudioObjectPropertyScopeGlobal, element: kAudioObjectPropertyElementMain, type: .string,  target: .device, settable: false),
    KnownProp(name: "sample-rate",   description: "Sample rate (Hz)",           selector: kAudioDevicePropertyNominalSampleRate, propScope: kAudioObjectPropertyScopeGlobal, element: kAudioObjectPropertyElementMain, type: .float64, target: .device, settable: true),
    KnownProp(name: "buffer-size",   description: "I/O buffer size (frames)",   selector: kAudioDevicePropertyBufferFrameSize,   propScope: kAudioObjectPropertyScopeGlobal, element: kAudioObjectPropertyElementMain, type: .uint32,  target: .device, settable: true),
    KnownProp(name: "latency",       description: "Device latency (frames)",    selector: kAudioDevicePropertyLatency,           propScope: kAudioObjectPropertyScopeGlobal, element: kAudioObjectPropertyElementMain, type: .uint32,  target: .device, settable: false),
    KnownProp(name: "safety-offset", description: "Safety offset (frames)",     selector: kAudioDevicePropertySafetyOffset,      propScope: kAudioObjectPropertyScopeGlobal, element: kAudioObjectPropertyElementMain, type: .uint32,  target: .device, settable: false),
    KnownProp(name: "transport",     description: "Transport type (UInt32)",    selector: kAudioDevicePropertyTransportType,     propScope: kAudioObjectPropertyScopeGlobal, element: kAudioObjectPropertyElementMain, type: .uint32,  target: .device, settable: false),
    KnownProp(name: "is-running",    description: "I/O is active (0/1)",        selector: kAudioDevicePropertyDeviceIsRunning,   propScope: kAudioObjectPropertyScopeGlobal, element: kAudioObjectPropertyElementMain, type: .uint32,  target: .device, settable: false),
    KnownProp(name: "is-hidden",     description: "Hidden device flag (0/1)",   selector: kAudioDevicePropertyIsHidden,          propScope: kAudioObjectPropertyScopeGlobal, element: kAudioObjectPropertyElementMain, type: .uint32,  target: .device, settable: false),

    // ── Control objects (child of device) ─────────────────────────────────────
    KnownProp(name: "volume",        description: "Output volume scalar (0–1)", selector: kAudioLevelControlPropertyScalarValue,  propScope: kAudioObjectPropertyScopeGlobal, element: kAudioObjectPropertyElementMain, type: .float32, target: .control(classID: kAudioVolumeControlClassID,    scope: kAudioObjectPropertyScopeOutput), settable: true),
    KnownProp(name: "volume-db",     description: "Output volume (dB)",         selector: kAudioLevelControlPropertyDecibelValue, propScope: kAudioObjectPropertyScopeGlobal, element: kAudioObjectPropertyElementMain, type: .float32, target: .control(classID: kAudioVolumeControlClassID,    scope: kAudioObjectPropertyScopeOutput), settable: true),
    KnownProp(name: "volume-input",  description: "Input volume scalar (0–1)",  selector: kAudioLevelControlPropertyScalarValue,  propScope: kAudioObjectPropertyScopeGlobal, element: kAudioObjectPropertyElementMain, type: .float32, target: .control(classID: kAudioVolumeControlClassID,    scope: kAudioObjectPropertyScopeInput),  settable: true),
    KnownProp(name: "mute",          description: "Output mute (0/1)",          selector: kAudioBooleanControlPropertyValue,      propScope: kAudioObjectPropertyScopeGlobal, element: kAudioObjectPropertyElementMain, type: .uint32,  target: .control(classID: kAudioMuteControlClassID,     scope: kAudioObjectPropertyScopeOutput), settable: true),
    KnownProp(name: "mute-input",    description: "Input mute (0/1)",           selector: kAudioBooleanControlPropertyValue,      propScope: kAudioObjectPropertyScopeGlobal, element: kAudioObjectPropertyElementMain, type: .uint32,  target: .control(classID: kAudioMuteControlClassID,     scope: kAudioObjectPropertyScopeInput),  settable: true),
    // BlackHole repurposes kAudioStereoPanControlClassID for pitch/speed adjustment.
    KnownProp(name: "pitch",         description: "Pitch/speed adj. (BlackHole)",selector: kAudioStereoPanControlPropertyValue,   propScope: kAudioObjectPropertyScopeGlobal, element: kAudioObjectPropertyElementMain, type: .float32, target: .control(classID: kAudioStereoPanControlClassID, scope: kAudioObjectPropertyScopeOutput), settable: true),
]

// MARK: - Property I/O

func resolveTarget(_ prop: KnownProp, deviceID: AudioObjectID) throws -> AudioObjectID {
    switch prop.target {
    case .device:
        return deviceID
    case .control(let classID, let scope):
        guard let cid = try findControl(ofClass: classID, under: deviceID, scope: scope) else {
            throw AudioCtrlError.controlNotFound(prop.name)
        }
        return cid
    }
}

func readProp(_ prop: KnownProp, objectID: AudioObjectID) throws -> String {
    let a = addr(prop.selector, prop.propScope, prop.element)
    switch prop.type {
    case .float32: return String(format: "%g", try getScalar(objectID, a) as Float32)
    case .float64: return String(format: "%g", try getScalar(objectID, a) as Float64)
    case .uint32:  return "\(try getScalar(objectID, a) as UInt32)"
    case .string:  return try getCFString(objectID, a)
    }
}

func writeProp(_ prop: KnownProp, objectID: AudioObjectID, value: String) throws {
    let a = addr(prop.selector, prop.propScope, prop.element)
    switch prop.type {
    case .float32:
        guard let v = Float32(value) else { throw AudioCtrlError.typeMismatch("expected Float32, got '\(value)'") }
        try setScalar(objectID, a, v)
    case .float64:
        guard let v = Float64(value) else { throw AudioCtrlError.typeMismatch("expected Float64, got '\(value)'") }
        try setScalar(objectID, a, v)
    case .uint32:
        guard let v = UInt32(value) else { throw AudioCtrlError.typeMismatch("expected UInt32, got '\(value)'") }
        try setScalar(objectID, a, v)
    case .string:
        throw AudioCtrlError.notSettable("\(prop.name) (string properties are not writable)")
    }
}

func readRaw(sel: AudioObjectPropertySelector, scope: AudioObjectPropertyScope, elem: AudioObjectPropertyElement, type: PropType, objectID: AudioObjectID) throws -> String {
    let a = addr(sel, scope, elem)
    switch type {
    case .float32: return String(format: "%g", try getScalar(objectID, a) as Float32)
    case .float64: return String(format: "%g", try getScalar(objectID, a) as Float64)
    case .uint32:  return "\(try getScalar(objectID, a) as UInt32)"
    case .string:  return try getCFString(objectID, a)
    }
}

func writeRaw(sel: AudioObjectPropertySelector, scope: AudioObjectPropertyScope, elem: AudioObjectPropertyElement, type: PropType, objectID: AudioObjectID, value: String) throws {
    let a = addr(sel, scope, elem)
    switch type {
    case .float32:
        guard let v = Float32(value) else { throw AudioCtrlError.typeMismatch("expected Float32") }
        try setScalar(objectID, a, v)
    case .float64:
        guard let v = Float64(value) else { throw AudioCtrlError.typeMismatch("expected Float64") }
        try setScalar(objectID, a, v)
    case .uint32:
        guard let v = UInt32(value) else { throw AudioCtrlError.typeMismatch("expected UInt32") }
        try setScalar(objectID, a, v)
    case .string:
        throw AudioCtrlError.notSettable("string (not writable via raw selector)")
    }
}

func scopeFrom(_ s: String) throws -> AudioObjectPropertyScope {
    switch s.lowercased() {
    case "global", "g": return kAudioObjectPropertyScopeGlobal
    case "input",  "i": return kAudioObjectPropertyScopeInput
    case "output", "o": return kAudioObjectPropertyScopeOutput
    default: throw ValidationError("Invalid scope '\(s)'. Use: global, input, output.")
    }
}

// MARK: - Table formatting helpers

private func ljust(_ s: String, _ w: Int) -> String {
    s.count >= w ? String(s.prefix(w)) : s + String(repeating: " ", count: w - s.count)
}
private func rjust(_ s: String, _ w: Int) -> String {
    s.count >= w ? s : String(repeating: " ", count: w - s.count) + s
}

// MARK: - Entry point

@main
struct AudioCtrl: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "audioctrl",
        abstract: "Read and write CoreAudio device properties from the command line.",
        subcommands: [List.self, Get.self, Set.self, Props.self]
    )
}

// MARK: - list

extension AudioCtrl {
    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "list",
            abstract: "List all audio devices."
        )

        @Flag(name: .shortAndLong, help: "Also print device UIDs.")
        var verbose = false

        mutating func run() throws {
            let devices = try getAllDeviceIDs()

            print("\(rjust("ID", 6))  \(ljust("Name", 32))  \(rjust("Rate", 7))  \(rjust("In", 3))  \(rjust("Out", 3))  Transport")
            print(String(repeating: "-", count: 70))

            for id in devices {
                let name  = deviceName(id)
                let rate  = getSampleRate(id).map { String(format: "%.0f", $0) } ?? "?"
                let inCh  = getChannelCount(id, scope: kAudioObjectPropertyScopeInput)
                let outCh = getChannelCount(id, scope: kAudioObjectPropertyScopeOutput)
                let tt    = (try? getScalar(id, addr(kAudioDevicePropertyTransportType)) as UInt32) ?? 0
                let trunc = name.count > 32 ? String(name.prefix(31)) + "…" : name

                print("\(rjust(String(id), 6))  \(ljust(trunc, 32))  \(rjust(rate, 7))  \(rjust(String(inCh), 3))  \(rjust(String(outCh), 3))  \(transportTypeName(tt))")
                if verbose {
                    print(String(repeating: " ", count: 8) + deviceUID(id))
                }
            }
        }
    }
}

// MARK: - get

extension AudioCtrl {
    struct Get: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "get",
            abstract: "Get a property value from a device.",
            discussion: """
            PROPERTY is a known name (see `audioctrl props`) or a raw CoreAudio selector:
            a 4-char code (e.g. msrt), hex (e.g. 0x6D737274), or decimal.
            --type is required when using a raw selector.
            """
        )

        @Argument(help: "Device name (substring), UID, or numeric object ID.")
        var device: String

        @Argument(help: "Property name or raw selector.")
        var property: String

        @Option(name: .shortAndLong, help: "Value type for raw selectors: float32, float64, uint32, string.")
        var type: PropType?

        @Option(name: .shortAndLong, help: "Property scope for raw selectors: global, input, output. (default: global)")
        var scope: String = "global"

        @Option(name: .shortAndLong, help: "Property element for raw selectors. (default: 0)")
        var element: UInt32 = 0

        mutating func run() throws {
            let deviceID = try findDevice(matching: device)

            if let known = knownProps.first(where: { $0.name == property }) {
                let targetID = try resolveTarget(known, deviceID: deviceID)
                print(try readProp(known, objectID: targetID))
            } else if let sel = parseSelector(property) {
                guard let t = type else {
                    throw ValidationError("'\(property)' is not a known property. Pass --type (float32|float64|uint32|string) to read it as a raw selector.")
                }
                print(try readRaw(sel: sel, scope: scopeFrom(scope), elem: element, type: t, objectID: deviceID))
            } else {
                throw AudioCtrlError.unknownProperty(property)
            }
        }
    }
}

// MARK: - set

extension AudioCtrl {
    struct Set: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "set",
            abstract: "Set a property value on a device.",
            discussion: """
            PROPERTY is a known name (see `audioctrl props`) or a raw CoreAudio selector.
            --type is required when using a raw selector.
            """
        )

        @Argument(help: "Device name (substring), UID, or numeric object ID.")
        var device: String

        @Argument(help: "Property name or raw selector.")
        var property: String

        @Argument(help: "New value.")
        var value: String

        @Option(name: .shortAndLong, help: "Value type for raw selectors: float32, float64, uint32, string.")
        var type: PropType?

        @Option(name: .shortAndLong, help: "Property scope for raw selectors: global, input, output. (default: global)")
        var scope: String = "global"

        @Option(name: .shortAndLong, help: "Property element for raw selectors. (default: 0)")
        var element: UInt32 = 0

        mutating func run() throws {
            let deviceID = try findDevice(matching: device)

            if let known = knownProps.first(where: { $0.name == property }) {
                guard known.settable else { throw AudioCtrlError.notSettable(property) }
                let targetID = try resolveTarget(known, deviceID: deviceID)
                try writeProp(known, objectID: targetID, value: value)
                print("Set \(property) → \(value)")
            } else if let sel = parseSelector(property) {
                guard let t = type else {
                    throw ValidationError("'\(property)' is not a known property. Pass --type (float32|float64|uint32|string) to write it as a raw selector.")
                }
                try writeRaw(sel: sel, scope: scopeFrom(scope), elem: element, type: t, objectID: deviceID, value: value)
                print("Set \(fourCC(sel)) → \(value)")
            } else {
                throw AudioCtrlError.unknownProperty(property)
            }
        }
    }
}

// MARK: - props

extension AudioCtrl {
    struct Props: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "props",
            abstract: "List all known property names and their types."
        )

        mutating func run() {
            let nw = knownProps.map(\.name.count).max()!
            let tw = PropType.allCases.map(\.rawValue.count).max()!

            print("  \(ljust("Name", nw))  \(ljust("Type", tw))  R/W  Description")
            print("  " + String(repeating: "-", count: nw + tw + 24))
            for p in knownProps {
                let rw = p.settable ? "r/w" : "r  "
                print("  \(ljust(p.name, nw))  \(ljust(p.type.rawValue, tw))  \(rw)  \(p.description)")
            }
        }
    }
}
