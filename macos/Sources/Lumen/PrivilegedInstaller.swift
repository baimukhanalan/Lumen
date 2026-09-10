import Foundation
import LumenCore

/// Installs / updates / removes the root LaunchDaemon.
///
/// Because CLT-only builds have neither code signing nor `SMAppService`, the
/// one privileged step is performed with AppleScript's
/// `do shell script … with administrator privileges`, which shows the native
/// macOS authorization dialog — the user types their own password, which this
/// code never sees.
///
/// The type is intentionally small and self-contained so it can later be
/// swapped for an `SMAppService` + XPC implementation without touching callers.
enum PrivilegedInstaller {

    enum Result {
        case success
        case cancelled
        case failure(String)
    }

    // MARK: - Queries (no privileges required)

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: Paths.launchDaemonPlist)
            && FileManager.default.fileExists(atPath: Paths.daemonInstallPath)
    }

    /// The daemon binary shipped inside the app bundle.
    static var bundledDaemonPath: String? {
        Bundle.main.url(forResource: "lumen-daemon", withExtension: nil)?.path
    }

    // MARK: - Actions

    /// Copy the daemon + plist into place and bootstrap the LaunchDaemon.
    static func installOrUpdate() -> Result {
        guard let daemonSrc = bundledDaemonPath,
              FileManager.default.fileExists(atPath: daemonSrc) else {
            return .failure("Bundled daemon binary not found in app resources.")
        }

        // Write the finalized plist to a user-writable temp file, baking in this
        // user's home so the root daemon can find the config and session logs.
        let plist = launchDaemonPlist(userHome: NSHomeDirectory())
        let tmpDir = NSTemporaryDirectory()
        let plistTmp = tmpDir + "com.lumen.daemon.plist"
        do {
            try plist.write(toFile: plistTmp, atomically: true, encoding: .utf8)
        } catch {
            return .failure("Could not stage plist: \(error.localizedDescription)")
        }

        let script = installShellScript(daemonSrc: daemonSrc, plistTmp: plistTmp)
        return runPrivileged(script)
    }

    /// Stop and remove the LaunchDaemon and binary.
    static func uninstall() -> Result {
        let script = """
        #!/bin/sh
        launchctl bootout system/\(Paths.daemonLabel) 2>/dev/null || true
        rm -f '\(Paths.launchDaemonPlist)'
        rm -f '\(Paths.daemonInstallPath)'
        """
        return runPrivileged(script)
    }

    // MARK: - Script assembly

    private static func installShellScript(daemonSrc: String, plistTmp: String) -> String {
        let daemon = shSingleQuote(daemonSrc)
        let plistDst = shSingleQuote(Paths.launchDaemonPlist)
        let plistSrc = shSingleQuote(plistTmp)
        let daemonDst = shSingleQuote(Paths.daemonInstallPath)
        return """
        #!/bin/sh
        set -e
        mkdir -p /usr/local/libexec /var/log
        cp \(daemon) \(daemonDst)
        chown root:wheel \(daemonDst)
        chmod 755 \(daemonDst)
        cp \(plistSrc) \(plistDst)
        chown root:wheel \(plistDst)
        chmod 644 \(plistDst)
        launchctl bootout system/\(Paths.daemonLabel) 2>/dev/null || true
        launchctl bootstrap system \(plistDst)
        launchctl enable system/\(Paths.daemonLabel) 2>/dev/null || true
        """
    }

    /// The LaunchDaemon plist. Runs the daemon as a persistent, relaunched
    /// process; the daemon owns its own poll interval.
    private static func launchDaemonPlist(userHome: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(Paths.daemonLabel)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(Paths.daemonInstallPath)</string>
            </array>
            <key>EnvironmentVariables</key>
            <dict>
                <key>\(Paths.userHomeEnvVar)</key>
                <string>\(xmlEscape(userHome))</string>
            </dict>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <true/>
            <key>ProcessType</key>
            <string>Background</string>
            <key>StandardOutPath</key>
            <string>/var/log/lumen-daemon.out.log</string>
            <key>StandardErrorPath</key>
            <string>/var/log/lumen-daemon.err.log</string>
        </dict>
        </plist>
        """
    }

    // MARK: - AppleScript privileged execution

    private static func runPrivileged(_ shellScript: String) -> Result {
        // Stage the shell script in a temp file so we don't have to embed a
        // multi-line command inside the AppleScript string literal.
        let scriptPath = NSTemporaryDirectory() + "lumen-install-\(UUID().uuidString).sh"
        do {
            try shellScript.write(toFile: scriptPath, atomically: true, encoding: .utf8)
        } catch {
            return .failure("Could not stage installer script: \(error.localizedDescription)")
        }
        defer { try? FileManager.default.removeItem(atPath: scriptPath) }

        let source = """
        set p to "\(appleScriptEscape(scriptPath))"
        do shell script "/bin/sh " & quoted form of p with administrator privileges
        """

        guard let apple = NSAppleScript(source: source) else {
            return .failure("Could not create install script.")
        }
        var errorInfo: NSDictionary?
        apple.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let num = (errorInfo[NSAppleScript.errorNumber] as? Int) ?? 0
            if num == -128 { return .cancelled } // user cancelled the auth dialog
            let msg = (errorInfo[NSAppleScript.errorMessage] as? String) ?? "Unknown error"
            return .failure(msg)
        }
        return .success
    }

    // MARK: - Escaping helpers

    /// Wrap a path in single quotes for /bin/sh, escaping embedded quotes.
    private static func shSingleQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Escape for an AppleScript double-quoted string literal.
    private static func appleScriptEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func xmlEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
    }
}
