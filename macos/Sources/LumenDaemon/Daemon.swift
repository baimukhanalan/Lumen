import Foundation
import LumenCore

/// The root-privileged watcher. Polls every `pollSeconds`, evaluates the shared
/// decision, and toggles `pmset -a disablesleep` only on state change. It
/// persists its latch state to the state file and is safe across crashes and
/// reboots (relaunched by launchd `KeepAlive`; restores allow-sleep when idle
/// and on graceful termination).
public final class Daemon: @unchecked Sendable {

    private let paths: Paths
    private let probe: SystemProbe
    private let logger: FileLogger
    private let dryRun: Bool

    private let queue = DispatchQueue(label: "com.lumen.daemon.loop")
    private var timer: DispatchSourceTimer?
    private var signalSources: [DispatchSourceSignal] = []

    /// Tracks wake-on-network so we only flip it on transitions.
    private var lastRemoteWomp = false

    public init(paths: Paths, dryRun: Bool) {
        self.paths = paths
        self.probe = SystemProbe(paths: paths)
        self.dryRun = dryRun
        // Echo to stderr as well, so `launchd` StandardErrorPath captures it.
        self.logger = FileLogger(path: paths.daemonLog, echoToStderr: true)
    }

    // MARK: - Lifecycle

    /// Runs a single evaluation and returns. Used for `--once`/tests.
    public func runOnce() {
        evaluate()
    }

    /// Starts the poll loop and blocks forever (until a termination signal).
    public func runLoop() -> Never {
        logger.log("lumen-daemon \(LumenVersion.string) starting (user home: \(paths.userHome))")
        installSignalHandlers()

        // Evaluate immediately so a relaunch restores a safe state without
        // waiting a full interval.
        evaluate()

        let interval = max(1, ConfigStore.load(at: paths.configFile).pollSeconds)
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + .seconds(interval), repeating: .seconds(interval))
        t.setEventHandler { [weak self] in self?.evaluate() }
        t.resume()
        self.timer = t

        dispatchMain()
    }

    private func installSignalHandlers() {
        for sig in [SIGTERM, SIGINT] {
            signal(sig, SIG_IGN) // prevent default termination; handle via source
            let src = DispatchSource.makeSignalSource(signal: sig, queue: queue)
            src.setEventHandler { [weak self] in self?.shutdown() }
            src.resume()
            signalSources.append(src)
        }
    }

    /// Restore the OS default (allow sleep) then exit. This is the self-heal
    /// guarantee for graceful termination.
    private func shutdown() {
        logger.log("received termination signal → restoring allow-sleep and exiting")
        if !dryRun { probe.setDisableSleep(false) }
        exit(0)
    }

    // MARK: - One poll

    private func evaluate() {
        let config = ConfigStore.load(at: paths.configFile)
        let now = Date()
        let nowEpoch = now.timeIntervalSince1970

        // Manual override channels: config `mode`, on-disk flag files, and an
        // active timed session all feed forceOn/forceOff.
        let fm = FileManager.default
        let flagOn = fm.fileExists(atPath: paths.forceOnFlag)
        let flagOff = fm.fileExists(atPath: paths.forceOffFlag)
        let timedActive = config.timedUntil > nowEpoch

        let forceOff = (config.mode == .off) || flagOff
        let forceOn = (config.mode == .on || config.mode == .remote) || flagOn || timedActive

        // Inputs.
        let sessionActive = probe.sessionActive(config: config, now: now)
        let processActive = probe.processActive(config: config)
        let power = probe.powerState()
        let thermalSerious = probe.thermalSerious()

        // Latch state from last poll.
        let prev = StateStore.load(at: paths.stateFile)
        let onSince = prev?.onSince ?? 0
        let capped = prev?.capped ?? false

        let decision = DecisionEngine.evaluate(DecisionInputs(
            forceOn: forceOn,
            forceOff: forceOff,
            sessionActive: sessionActive,
            processActive: processActive,
            onBattery: power.onBattery,
            batteryPercent: power.percent,
            thermalSerious: thermalSerious,
            criticalBatteryPercent: config.criticalBatteryPercent,
            batteryFloorPercent: config.batteryFloorPercent,
            acOnly: config.acOnly,
            maxHours: config.maxHours,
            now: nowEpoch,
            onSince: onSince,
            capped: capped
        ))

        // Apply only on change.
        let currentlyDisabled = probe.sleepDisabled()
        if dryRun {
            logger.log("DRYRUN want=\(decision.shouldStayAwake) have=\(currentlyDisabled) reason=\(decision.reason)")
        } else if decision.shouldStayAwake != currentlyDisabled {
            probe.setDisableSleep(decision.shouldStayAwake)
            logger.log(decision.shouldStayAwake
                ? "keep awake → disablesleep 1 (lid may be closed) — \(decision.reason)"
                : "allow sleep → disablesleep 0 — \(decision.reason)")
        }

        // Remote mode manages wake-on-network on AC.
        let wantWomp = (config.mode == .remote) && !power.onBattery
        if !dryRun, wantWomp != lastRemoteWomp {
            probe.setWakeOnNetwork(wantWomp)
            lastRemoteWomp = wantWomp
            logger.log("remote mode → womp \(wantWomp ? 1 : 0)")
        }

        // Publish state (also our persistence).
        let appliedDisabled = dryRun ? currentlyDisabled : decision.shouldStayAwake
        let state = DaemonState(
            shouldStayAwake: decision.shouldStayAwake,
            sleepDisabled: appliedDisabled,
            reason: decision.reason,
            mode: config.mode,
            sessionActive: sessionActive,
            processActive: processActive,
            onBattery: power.onBattery,
            batteryPercent: power.percent,
            thermal: probe.thermalName(),
            timedUntil: config.timedUntil,
            onSince: decision.onSince,
            capped: decision.capped,
            updatedAt: nowEpoch,
            daemonVersion: LumenVersion.string
        )
        StateStore.save(state, to: paths.stateFile)
    }
}
