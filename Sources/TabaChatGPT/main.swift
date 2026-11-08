import Foundation
import ResponsesKit

/// Writes a line to stderr. Output here never includes a token, a code, a verifier or a header.
func complain(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

let arguments = Array(CommandLine.arguments.dropFirst())
let usage = """
usage:
  taba-chatgpt sign-in
  taba-chatgpt probe --model <name> [--out <directory>]
"""

switch arguments.first {
case "sign-in":
    exit(await SignInCommand.run())
case "probe":
    exit(await ProbeCommand.run(arguments: Array(arguments.dropFirst())))
default:
    complain(usage)
    exit(2)
}
