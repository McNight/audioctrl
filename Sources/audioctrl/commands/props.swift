import ArgumentParser
import CoreAudio

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
