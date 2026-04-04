import ArgumentParser
import CoreAudio
import Foundation

// MARK: - Sort key for list

enum SortKey: String, CaseIterable, ExpressibleByArgument {
    case transport, id, name, rate

    init?(argument: String) { self.init(rawValue: argument.lowercased()) }
}

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

// MARK: - Entry point

@main
struct AudioCtrl: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "audioctrl",
        abstract: "Read and write CoreAudio device properties from the command line.",
        subcommands: [List.self, Get.self, Set.self, Props.self]
    )
}
