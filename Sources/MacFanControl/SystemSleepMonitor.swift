import Foundation
import IOKit
import IOKit.pwr_mgt
import IOReportBridge

/// Shared by the power-notification, command, and main queues.
final class FanPowerLifecycle: @unchecked Sendable {
    struct Snapshot {
        let generation: UInt64
        let sleeping: Bool
        let handoffPending: Bool
        let wakeTime: DispatchTime?

        var permitsWrites: Bool { !sleeping && !handoffPending }

        func acceptsSamples(temperature: DispatchTime?, fanRPM: DispatchTime?) -> Bool {
            guard permitsWrites else { return false }
            guard let wakeTime else { return true }
            guard let temperature, let fanRPM else { return false }
            return temperature >= wakeTime && fanRPM >= wakeTime
        }
    }

    private let lock = NSLock()
    private var generation: UInt64 = 0
    private var sleeping = false
    private var handoffPending = false
    private var wakeTime: DispatchTime?

    var snapshot: Snapshot {
        lock.withLock {
            Snapshot(generation: generation, sleeping: sleeping, handoffPending: handoffPending, wakeTime: wakeTime)
        }
    }

    func beginSleep() -> UInt64 {
        lock.withLock {
            generation += 1
            sleeping = true
            handoffPending = true
            wakeTime = nil
            return generation
        }
    }

    func finishHandoff(generation: UInt64) {
        lock.withLock {
            guard self.generation == generation else { return }
            handoffPending = false
        }
    }

    @discardableResult
    func wake(at time: DispatchTime = .now()) -> Bool {
        lock.withLock {
            guard sleeping else { return false }
            sleeping = false
            wakeTime = time
            return true
        }
    }

    func permitsWrite(generation: UInt64) -> Bool {
        let state = snapshot
        return state.generation == generation && state.permitsWrites
    }
}

/// Acknowledges system sleep on the power queue even if a hardware command stalls.
final class SystemSleepMonitor: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.ifancontrol.system-power", qos: .userInitiated)
    private let lifecycle: FanPowerLifecycle
    private let handoff: @Sendable (UInt64, @escaping @Sendable (Bool) -> Void) -> Void
    private let handoffBudget: DispatchTimeInterval = .seconds(2)
    private var connection: io_connect_t = 0
    private var port: IONotificationPortRef?
    private var notifier: io_object_t = 0
    private var pendingAcknowledgements: [Int: UInt64] = [:]

    init(lifecycle: FanPowerLifecycle,
         handoff: @escaping @Sendable (UInt64, @escaping @Sendable (Bool) -> Void) -> Void) {
        self.lifecycle = lifecycle
        self.handoff = handoff
    }

    func start() {
        queue.sync {
            guard connection == 0 else { return }
            connection = IORegisterForSystemPower(Unmanaged.passUnretained(self).toOpaque(), &port, { context, _, message, argument in
                guard let context else { return }
                let monitor = Unmanaged<SystemSleepMonitor>.fromOpaque(context).takeUnretainedValue()
                monitor.receive(message: message, token: Int(bitPattern: argument))
            }, &notifier)
            guard connection != 0, let port else {
                AppLog.shared.error("fan sleep: power notification registration failed")
                return
            }
            IONotificationPortSetDispatchQueue(port, queue)
            AppLog.shared.info("fan sleep: registered system power notifications")
        }
    }

    func stop() {
        queue.sync {
            guard connection != 0, let port else { return }
            for (token, generation) in Array(pendingAcknowledgements) {
                acknowledge(token: token, generation: generation, outcome: "app_exit")
            }
            IODeregisterForSystemPower(&notifier)
            IONotificationPortDestroy(port)
            IOServiceClose(connection)
            connection = 0
            self.port = nil
        }
    }

    private func receive(message: natural_t, token: Int) {
        switch message {
        case IFanCanSystemSleep:
            _ = IOAllowPowerChange(connection, token)
        case IFanSystemWillSleep:
            let generation = lifecycle.beginSleep()
            pendingAcknowledgements[token] = generation
            AppLog.shared.info("fan sleep: will sleep generation=\(generation) requesting system control")
            queue.asyncAfter(deadline: .now() + handoffBudget) { [weak self] in
                self?.acknowledge(token: token, generation: generation, outcome: "timeout")
            }
            handoff(generation) { [weak self] success in
                guard let self else { return }
                self.queue.async {
                    self.lifecycle.finishHandoff(generation: generation)
                    AppLog.shared.info("fan sleep: handoff command completed generation=\(generation) success=\(success)")
                    self.acknowledge(token: token, generation: generation, outcome: success ? "command_succeeded" : "command_failed")
                }
            }
        case IFanSystemHasPoweredOn:
            if lifecycle.wake() {
                AppLog.shared.info("fan sleep: woke generation=\(lifecycle.snapshot.generation) waiting for fresh telemetry")
            }
        default:
            break
        }
    }

    private func acknowledge(token: Int, generation: UInt64, outcome: String) {
        guard pendingAcknowledgements[token] == generation else { return }
        pendingAcknowledgements.removeValue(forKey: token)
        let result = IOAllowPowerChange(connection, token)
        AppLog.shared.info("fan sleep: acknowledged generation=\(generation) outcome=\(outcome) ioResult=\(result)")
    }
}
