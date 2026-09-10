import Foundation
import LumenCore

// Entry point for `lumen-daemon`.
//
// Usage:
//   lumen-daemon            run the poll loop (default; used by launchd)
//   lumen-daemon --once     evaluate a single time and exit
//   lumen-daemon --dry-run  evaluate without touching pmset (loop or --once)
//   lumen-daemon --version
//   lumen-daemon --help

let args = Array(CommandLine.arguments.dropFirst())

if args.contains("--help") || args.contains("-h") {
    print("""
    lumen-daemon \(LumenVersion.string)
      (no args)     run the poll loop (root; installed via LaunchDaemon)
      --once        evaluate once and exit
      --dry-run     do not change system sleep state; log the decision
      --version     print version and exit
      --help        show this help
    """)
    exit(0)
}

if args.contains("--version") {
    print(LumenVersion.string)
    exit(0)
}

let dryRun = args.contains("--dry-run")
let once = args.contains("--once")

// The daemon resolves the interactive user (see Paths.forConsoleUser).
let paths = Paths.forConsoleUser()
let daemon = Daemon(paths: paths, dryRun: dryRun)

if once {
    daemon.runOnce()
    exit(0)
} else {
    daemon.runLoop()
}
