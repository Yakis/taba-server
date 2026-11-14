import Foundation
import GuideScoreKit

exit(await ScoreCLI.run(Array(CommandLine.arguments.dropFirst()), environment: ProcessInfo.processInfo.environment))
