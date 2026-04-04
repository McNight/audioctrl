import ArgumentParser
import CoreAudio

extension AudioCtrl {
    struct Get: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "get",
            abstract: "Get a property value from a device.",
            discussion: """
            Examples:
              audioctrl get Speakers volume        Get output volume by name substring
              audioctrl get 116 sample-rate         Get sample rate by device ID
              audioctrl get --id 116 sample-rate    Same, using --id flag
              audioctrl get Speakers                Dump all readable properties

            PROPERTY is a known name (see `audioctrl props`) or a raw CoreAudio
            selector (4-char code, hex, or decimal). Use --type with raw selectors.
            Omit PROPERTY to dump all known properties for the device.
            """
        )

        @Argument(help: "Device (name substring, UID, or ID) and optional property name.")
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
            let property: String?

            if hasFlagDevice {
                guard positionals.count <= 1 else {
                    throw ValidationError("Expected at most <property> when using --name or --id.")
                }
                deviceID = try AudioObjectID.resolve(name: name, id: id)
                property = positionals.first
            } else {
                guard (1...2).contains(positionals.count) else {
                    throw ValidationError("Expected <device> [property]. Use --id or --name to select by flag.")
                }
                deviceID = try AudioObjectID.findDevice(matching: positionals[0])
                property = positionals.count == 1 ? nil : positionals[1]
            }

            if let property {
                if let known = knownProps.first(where: { $0.name == property }) {
                    print(try known.targetID(for: deviceID)[known])
                } else if let sel = parseSelector(property) {
                    guard let t = type else {
                        throw ValidationError("'\(property)' is not a known property. Pass --type (float32|float64|uint32|string) to read it as a raw selector.")
                    }
                    print(try deviceID.readRaw(sel: sel, scope: .from(scope), elem: element, type: t))
                } else {
                    throw AudioCtrlError.unknownProperty(property)
                }
            } else {
                dumpAllProperties(deviceID: deviceID)
            }
        }

        private func dumpAllProperties(deviceID: AudioObjectID) {
            // Collect known-prop rows, tracking which control object IDs they cover.
            struct Row { let name: String; let value: String; let annotation: String }
            var rows: [Row] = []
            var coveredControlIDs = Swift.Set<AudioObjectID>()

            for prop in knownProps {
                guard let targetID = try? prop.targetID(for: deviceID),
                      let value   = try? targetID[prop] else { continue }
                let annotation: String
                switch prop.target {
                case .device: annotation = ""
                case .control(_, let scope):
                    switch scope {
                    case kAudioObjectPropertyScopeInput:  annotation = "input"
                    case kAudioObjectPropertyScopeOutput: annotation = "output"
                    default:                              annotation = "global"
                    }
                }
                rows.append(Row(name: prop.name, value: value, annotation: annotation))
                coveredControlIDs.insert(targetID)
            }

            // Append any controls not covered by a known prop (unknown/device-specific).
            if let controls = try? deviceID.controls {
                for c in controls where !coveredControlIDs.contains(c.objectID) {
                    rows.append(Row(name: c.className, value: "—", annotation: c.scope))
                }
            }

            let nw = rows.map(\.name.count).max() ?? 0
            let vw = rows.map(\.value.count).max() ?? 0
            for row in rows {
                if row.annotation.isEmpty {
                    print("  \(ljust(row.name, nw))  \(row.value)")
                } else {
                    print("  \(ljust(row.name, nw))  \(ljust(row.value, vw))  [\(row.annotation)]")
                }
            }
        }
    }
}
