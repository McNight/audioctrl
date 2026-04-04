import ArgumentParser
import CoreAudio

extension AudioCtrl {
    struct Set: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "set",
            abstract: "Set a property value on a device.",
            discussion: """
            Examples:
              audioctrl set Speakers volume 0.8         Set output volume by name substring
              audioctrl set 116 sample-rate 48000        Set sample rate by device ID
              audioctrl set --id 116 volume 0.5          Same, using --id flag

            PROPERTY is a known name (see `audioctrl props`) or a raw CoreAudio
            selector (4-char code, hex, or decimal). Use --type with raw selectors.
            """
        )

        @Argument(help: "Device (name/UID/ID), property name, and value.")
        var positionals: [String] = []

        @Option(name: [.customShort("n"), .long], help: "Select device by name (substring or UID).")
        var name: String?

        @Option(name: [.customShort("i"), .long], help: "Select device by numeric object ID.")
        var id: UInt32?

        @Option(name: .shortAndLong, help: "Value type for raw selectors: float32, float64, uint32, string.")
        var type: PropType?

        @Option(name: .shortAndLong, help: "Property scope: global, input, output. (default: global)")
        var scope: String = "global"

        @Option(name: .shortAndLong, help: "Property element. (default: 0)")
        var element: UInt32 = 0

        mutating func run() throws {
            let hasFlagDevice = name != nil || id != nil
            let deviceID: AudioObjectID
            let property: String
            let value: String

            if hasFlagDevice {
                guard positionals.count == 2 else {
                    throw ValidationError("Expected <property> <value> when using --name or --id.")
                }
                deviceID = try AudioObjectID.resolve(name: name, id: id)
                property = positionals[0]
                value    = positionals[1]
            } else {
                guard positionals.count == 3 else {
                    throw ValidationError("Expected <device> <property> <value>. Use --id or --name to select by flag.")
                }
                deviceID = try AudioObjectID.findDevice(matching: positionals[0])
                property = positionals[1]
                value    = positionals[2]
            }

            if let known = knownProps.first(where: { $0.name == property }) {
                guard known.settable else { throw AudioCtrlError.notSettable(property) }
                try known.targetID(for: deviceID).writeProp(known, value: value)
                print("Set \(property) → \(value)")
            } else if let sel = parseSelector(property) {
                guard let t = type else {
                    throw ValidationError("'\(property)' is not a known property. Pass --type (float32|float64|uint32|string) to write it as a raw selector.")
                }
                try deviceID.writeRaw(sel: sel, scope: .from(scope), elem: element, type: t, value: value)
                print("Set \(fourCC(sel)) → \(value)")
            } else {
                throw AudioCtrlError.unknownProperty(property)
            }
        }
    }
}
