import Foundation
import MacFanControlCore

let exitCode = MacFanControlHelperCLI.run(arguments: Array(CommandLine.arguments.dropFirst()))
exit(exitCode.rawValue)
