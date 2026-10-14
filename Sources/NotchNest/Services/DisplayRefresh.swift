import Foundation

/// Bounded settling after HDMI/sleep changes. An empty intermediate snapshot
/// never cancels recovery without scheduling another check.
@MainActor
final class DisplayRefresh {
    private(set) var target: NotchDisplayTarget?
    private let source: () -> NotchDisplayTarget?
    private let apply: (NotchDisplayTarget?) -> Void
    private let settleDelay: TimeInterval
    private let maxAttempts: Int
    private var pending: DispatchWorkItem?
    private var asleep = false

    init(target: NotchDisplayTarget?, source: @escaping () -> NotchDisplayTarget?,
         settleDelay: TimeInterval = 0.4, maxAttempts: Int = 5,
         apply: @escaping (NotchDisplayTarget?) -> Void) {
        self.target = target
        self.source = source
        self.settleDelay = settleDelay
        self.maxAttempts = maxAttempts
        self.apply = apply
    }

    func refresh(displaysAsleep: Bool) {
        asleep = displaysAsleep
        if asleep {
            pending?.cancel()
            pending = nil
            publish(nil)
            return
        }
        let candidate = source()
        if let candidate, candidate == target {
            pending?.cancel()
            pending = nil
            return
        }
        publish(nil)
        recheck(attempts: maxAttempts)
    }

    private func recheck(attempts: Int) {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.asleep else { return }
            self.pending = nil
            if let candidate = self.source() {
                self.publish(candidate)
            } else if attempts > 1 {
                self.recheck(attempts: attempts - 1)
            }
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + settleDelay, execute: work)
    }

    private func publish(_ value: NotchDisplayTarget?) {
        guard target != value else { return }
        target = value
        apply(value)
    }

    deinit { pending?.cancel() }
}
