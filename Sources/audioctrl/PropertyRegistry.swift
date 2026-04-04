import CoreAudio

// kAudioControlPropertyScope = 'cscp'
let kAudioControlPropertyScopeSelector: AudioObjectPropertySelector = 0x63736370

struct ControlInfo {
    let objectID: AudioObjectID
    let classID: AudioClassID
    let className: String
    let scope: String
}

struct KnownProp {
    let name: String
    let description: String
    let selector: AudioObjectPropertySelector
    let propScope: AudioObjectPropertyScope
    let element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    let type: PropType
    let target: PropTarget
    let settable: Bool
}

extension KnownProp {
    var addr: AudioObjectPropertyAddress {
        audioctrl.addr(selector, propScope, element)
    }

    func targetID(for deviceID: AudioObjectID) throws -> AudioObjectID {
        switch target {
        case .device:
            return deviceID
        case .control(let classID, let scope):
            guard let cid = try deviceID.findControl(ofClass: classID, scope: scope) else {
                throw AudioCtrlError.controlNotFound(name)
            }
            return cid
        }
    }
}

let knownProps: [KnownProp] = [
    // ── Device-level ──────────────────────────────────────────────────────────
    KnownProp(name: "name",          description: "Device name",                selector: kAudioObjectPropertyName,              propScope: kAudioObjectPropertyScopeGlobal, type: .string,  target: .device, settable: false),
    KnownProp(name: "uid",           description: "Unique identifier (UID)",    selector: kAudioDevicePropertyDeviceUID,         propScope: kAudioObjectPropertyScopeGlobal, type: .string,  target: .device, settable: false),
    KnownProp(name: "model-uid",     description: "Model UID",                  selector: kAudioDevicePropertyModelUID,          propScope: kAudioObjectPropertyScopeGlobal, type: .string,  target: .device, settable: false),
    KnownProp(name: "sample-rate",   description: "Sample rate (Hz)",           selector: kAudioDevicePropertyNominalSampleRate, propScope: kAudioObjectPropertyScopeGlobal, type: .float64, target: .device, settable: true),
    KnownProp(name: "buffer-size",   description: "I/O buffer size (frames)",   selector: kAudioDevicePropertyBufferFrameSize,   propScope: kAudioObjectPropertyScopeGlobal, type: .uint32,  target: .device, settable: true),
    KnownProp(name: "latency",       description: "Device latency (frames)",    selector: kAudioDevicePropertyLatency,           propScope: kAudioObjectPropertyScopeGlobal, type: .uint32,  target: .device, settable: false),
    KnownProp(name: "safety-offset", description: "Safety offset (frames)",     selector: kAudioDevicePropertySafetyOffset,      propScope: kAudioObjectPropertyScopeGlobal, type: .uint32,  target: .device, settable: false),
    KnownProp(name: "transport",     description: "Transport type (UInt32)",    selector: kAudioDevicePropertyTransportType,     propScope: kAudioObjectPropertyScopeGlobal, type: .uint32,  target: .device, settable: false),
    KnownProp(name: "is-running",    description: "I/O is active (0/1)",        selector: kAudioDevicePropertyDeviceIsRunning,   propScope: kAudioObjectPropertyScopeGlobal, type: .uint32,  target: .device, settable: false),
    KnownProp(name: "is-hidden",     description: "Hidden device flag (0/1)",   selector: kAudioDevicePropertyIsHidden,          propScope: kAudioObjectPropertyScopeGlobal, type: .uint32,  target: .device, settable: false),

    // ── Control objects (child of device) ─────────────────────────────────────
    KnownProp(name: "volume",        description: "Output volume scalar (0–1)", selector: kAudioLevelControlPropertyScalarValue,  propScope: kAudioObjectPropertyScopeGlobal, type: .float32, target: .control(classID: kAudioVolumeControlClassID,    scope: kAudioObjectPropertyScopeOutput), settable: true),
    KnownProp(name: "volume-db",     description: "Output volume (dB)",         selector: kAudioLevelControlPropertyDecibelValue, propScope: kAudioObjectPropertyScopeGlobal, type: .float32, target: .control(classID: kAudioVolumeControlClassID,    scope: kAudioObjectPropertyScopeOutput), settable: true),
    KnownProp(name: "volume-input",  description: "Input volume scalar (0–1)",  selector: kAudioLevelControlPropertyScalarValue,  propScope: kAudioObjectPropertyScopeGlobal, type: .float32, target: .control(classID: kAudioVolumeControlClassID,    scope: kAudioObjectPropertyScopeInput),  settable: true),
    KnownProp(name: "mute",          description: "Output mute (0/1)",          selector: kAudioBooleanControlPropertyValue,      propScope: kAudioObjectPropertyScopeGlobal, type: .uint32,  target: .control(classID: kAudioMuteControlClassID,     scope: kAudioObjectPropertyScopeOutput), settable: true),
    KnownProp(name: "mute-input",    description: "Input mute (0/1)",           selector: kAudioBooleanControlPropertyValue,      propScope: kAudioObjectPropertyScopeGlobal, type: .uint32,  target: .control(classID: kAudioMuteControlClassID,     scope: kAudioObjectPropertyScopeInput),  settable: true),
    // BlackHole: clock source selector (0=Internal Fixed, 1=Internal Adjustable).
    // Must be set to 1 before the pitch control becomes available.
    KnownProp(name: "clock-source",  description: "Clock source (0=fixed, 1=adjustable)", selector: kAudioSelectorControlPropertyCurrentItem, propScope: kAudioObjectPropertyScopeGlobal, type: .uint32,  target: .control(classID: kAudioClockSourceControlClassID, scope: kAudioObjectPropertyScopeGlobal),  settable: true),
    // BlackHole: pitch/speed adjust via stereo-pan control. Only present when clock-source=1.
    KnownProp(name: "pitch",         description: "Pitch/speed (0.5=normal, BlackHole)", selector: kAudioStereoPanControlPropertyValue,      propScope: kAudioObjectPropertyScopeGlobal, type: .float32, target: .control(classID: kAudioStereoPanControlClassID, scope: kAudioObjectPropertyScopeOutput), settable: true),
]
