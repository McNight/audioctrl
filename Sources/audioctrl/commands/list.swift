import ArgumentParser
import CoreAudio

extension AudioCtrl {
    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "list",
            abstract: "List all audio devices."
        )

        @Flag(name: .shortAndLong, help: "Also print device UIDs.")
        var verbose = false

        @Option(name: .shortAndLong, help: "Sort by: transport (default), id, name, rate.")
        var sort: SortKey = .transport

        mutating func run() throws {
            let raw = try AudioObjectID.allDeviceIDs

            let devices: [AudioObjectID]
            switch sort {
            case .transport:
                devices = raw.sorted {
                    let ta = (try? $0.getScalarProperty(kAudioDevicePropertyTransportType) as UInt32) ?? 0
                    let tb = (try? $1.getScalarProperty(kAudioDevicePropertyTransportType) as UInt32) ?? 0
                    let oa = transportSortOrder(ta), ob = transportSortOrder(tb)
                    return oa != ob ? oa < ob : $0.deviceName < $1.deviceName
                }
            case .id:
                devices = raw.sorted()
            case .name:
                devices = raw.sorted { $0.deviceName < $1.deviceName }
            case .rate:
                devices = raw.sorted { ($0.sampleRate ?? 0) < ($1.sampleRate ?? 0) }
            }

            print("\(rjust("ID", 6))  \(ljust("Name", 32))  \(rjust("Rate", 7))  \(rjust("In", 3))  \(rjust("Out", 3))  Transport")
            print(String(repeating: "-", count: 70))

            for id in devices {
                let name  = id.deviceName
                let rate  = id.sampleRate.map { String(format: "%.0f", $0) } ?? "?"
                let inCh  = id.getChannelCount(scope: kAudioObjectPropertyScopeInput)
                let outCh = id.getChannelCount(scope: kAudioObjectPropertyScopeOutput)
                let tt    = (try? id.getScalarProperty(kAudioDevicePropertyTransportType) as UInt32) ?? 0
                let trunc = name.count > 32 ? String(name.prefix(31)) + "…" : name

                print("\(rjust(String(id), 6))  \(ljust(trunc, 32))  \(rjust(rate, 7))  \(rjust(String(inCh), 3))  \(rjust(String(outCh), 3))  \(transportTypeName(tt))")
                if verbose {
                    print(String(repeating: " ", count: 8) + id.deviceUID)
                }
            }
        }
    }
}
