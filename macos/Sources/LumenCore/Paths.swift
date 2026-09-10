import Foundation

/// Filesystem locations Lumen uses, resolved relative to a specific user's
/// home directory.
///
/// The subtlety on macOS is that the daemon runs as **root** (so `~` would be
/// `/var/root`), yet it must read the *interactive* user's config and session
/// logs. `Paths.forConsoleUser()` resolves that user; the UI, which already
/// runs as the user, uses `Paths.forCurrentUser()`.
public struct Paths: Sendable {

    /// Home directory these paths are anchored to (e.g. `/Users/alice`).
    public let userHome: String

    public init(userHome: String) {
        self.userHome = userHome
    }

    // MARK: Per-user, user-writable

    /// `~/Library/Application Support/Lumen`
    public var supportDir: String {
        userHome + "/Library/Application Support/Lumen"
    }

    /// Shared JSON config (schema in `shared/detection.md`).
    public var configFile: String { supportDir + "/config.json" }

    /// Manual-override flag files. Presence is a boolean; contents are ignored.
    /// They live in the user's support dir so the (non-root) UI can create and
    /// remove them without elevation, while the root daemon only reads them.
    public var forceOnFlag: String { supportDir + "/force-on" }
    public var forceOffFlag: String { supportDir + "/force-off" }

    /// Session-log directories watched for recent activity.
    public var claudeProjectsDir: String { userHome + "/.claude/projects" }
    public var codexSessionsDir: String { userHome + "/.codex/sessions" }

    // MARK: System-wide (root-owned)

    /// State the daemon publishes for the UI to read. `/var/run` is
    /// world-readable, so the UI can poll it without elevation.
    public var stateFile: String { "/var/run/lumen-state.json" }

    /// Daemon append-only log.
    public var daemonLog: String { "/var/log/lumen-daemon.log" }

    // MARK: Install locations (constants)

    public static let daemonInstallPath = "/usr/local/libexec/lumen-daemon"
    public static let launchDaemonPlist = "/Library/LaunchDaemons/com.lumen.daemon.plist"
    public static let daemonLabel = "com.lumen.daemon"

    /// Environment variable the daemon reads to learn the target user's home
    /// (baked into the LaunchDaemon plist by the installer).
    public static let userHomeEnvVar = "LUMEN_USER_HOME"

    // MARK: Resolvers

    /// Paths for the user currently running this process (the UI).
    public static func forCurrentUser() -> Paths {
        Paths(userHome: NSHomeDirectory())
    }

    /// Paths for the interactive/console user, resolved even when this process
    /// runs as root. Resolution order:
    ///   1. `LUMEN_USER_HOME` environment variable (set in the plist), then
    ///   2. the owner of `/dev/console` (the user logged in at the GUI), then
    ///   3. `NSHomeDirectory()` as a last resort.
    public static func forConsoleUser() -> Paths {
        let env = ProcessInfo.processInfo.environment
        if let home = env[userHomeEnvVar], !home.isEmpty {
            return Paths(userHome: home)
        }
        if let home = consoleUserHomeViaStat() {
            return Paths(userHome: home)
        }
        return Paths(userHome: NSHomeDirectory())
    }

    private static func consoleUserHomeViaStat() -> String? {
        var info = stat()
        guard stat("/dev/console", &info) == 0 else { return nil }
        let uid = info.st_uid
        // root (uid 0) means nobody is logged in at the GUI; not useful here.
        guard uid != 0, let pw = getpwuid(uid), let dir = pw.pointee.pw_dir else {
            return nil
        }
        return String(cString: dir)
    }
}
