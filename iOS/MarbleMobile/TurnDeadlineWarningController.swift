import Foundation

/// client(393) TurnDeadlineWarningController의 iOS 대응 계층.
/// 일반 presentation queue와 독립적으로 마지막 20초 tick/숫자 Voice/0초 SFX를 재생한다.
@MainActor
final class TurnDeadlineWarningController {
    static let thresholds = [20, 15, 10, 5, 0]

    private let audio: IOSAudioController
    private var generation = 0
    private var scheduled: [DispatchWorkItem] = []
    private var expired = false
    private var deadlineUptime: TimeInterval?
    private var zeroPlaying = false
    private var zeroWaiters: [() -> Void] = []

    init(audio: IOSAudioController) {
        self.audio = audio
    }

    @discardableResult
    func startForTurn(
        playerID: Int?,
        localPlayerID: Int?,
        turnGeneration: Int?,
        turnDeadlineAt: String?,
        turnRemainingSeconds: Double?
    ) -> Bool {
        stop(preserveZeroSFX: true)
        guard let playerID, let localPlayerID, playerID == localPlayerID,
              let turnGeneration, turnGeneration > 0,
              let remaining = resolvedRemainingSeconds(
                turnDeadlineAt: turnDeadlineAt,
                turnRemainingSeconds: turnRemainingSeconds
              ), remaining > 0
        else { return false }

        generation += 1
        let currentGeneration = generation
        expired = false
        deadlineUptime = ProcessInfo.processInfo.systemUptime + remaining

        let eligible = Self.thresholds.filter { Double($0) <= remaining + 0.05 }
        schedule(after: max(0, remaining - 20), generation: currentGeneration) { [weak self] in
            _ = self?.audio.startTurnWarningTick("ticktock.wav")
        }

        for seconds in eligible {
            let delay = max(0, remaining - Double(seconds))
            schedule(after: delay, generation: currentGeneration) { [weak self] in
                guard let self else { return }
                if seconds == 0 {
                    self.startZeroSFXIfNeeded()
                    return
                }
                _ = self.audio.playTurnWarningVoice("ticktock_\(seconds).wav")
            }
        }
        return true
    }

    /// TURN_ENDED/GAME_OVER에서는 0초 경계에 도달한 효과음을 자연스럽게 끝까지 보존한다.
    /// 서버 종료 메시지와 로컬 0초 DispatchWorkItem의 실행 순서가 뒤바뀌어도
    /// PC판의 preserve-expired-zero 계약처럼 경고음이 빠지지 않게 한다.
    func stop(preserveZeroSFX: Bool = false) {
        let zeroIsDue = isZeroDue
        generation += 1
        scheduled.forEach { $0.cancel() }
        scheduled.removeAll()

        if preserveZeroSFX && (expired || zeroPlaying || zeroIsDue) {
            audio.stopTurnWarningTickOnly()
            if !zeroPlaying && zeroIsDue {
                startZeroSFXIfNeeded()
            }
            deadlineUptime = nil
            return
        }

        expired = false
        deadlineUptime = nil
        audio.stopTurnWarningAudio()
        if zeroPlaying {
            zeroPlaying = false
            drainZeroWaiters()
        }
    }

    var hasPendingZeroSFX: Bool {
        zeroPlaying || isZeroDue
    }

    /// 다음 TURN_STARTED의 ordering barrier가 0초 SFX의 자연 완료를 기다릴 때 사용한다.
    /// 아직 zero callback이 실행되지 않았지만 deadline은 지난 race 구간이면 여기서
    /// 0초 SFX를 시작한 뒤 동일하게 완료를 기다린다.
    func waitForPendingZeroSFX(_ completion: @escaping () -> Void) {
        if !zeroPlaying && isZeroDue {
            startZeroSFXIfNeeded()
        }
        guard zeroPlaying else { completion(); return }
        zeroWaiters.append(completion)
    }


    private var isZeroDue: Bool {
        guard let deadlineUptime else { return false }
        return ProcessInfo.processInfo.systemUptime >= deadlineUptime
    }

    private func startZeroSFXIfNeeded() {
        guard !zeroPlaying else { return }
        expired = true
        deadlineUptime = nil
        scheduled.forEach { $0.cancel() }
        scheduled.removeAll()
        audio.stopTurnWarningTickOnly()
        zeroPlaying = true
        let started = audio.playTurnWarningZeroSFX("ticktock_0.WAV") { [weak self] in
            self?.finishZeroSFX()
        }
        if !started { finishZeroSFX() }
    }

    private func schedule(after seconds: Double, generation expectedGeneration: Int, action: @escaping () -> Void) {
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.generation == expectedGeneration else { return }
            action()
        }
        scheduled.append(item)
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, seconds), execute: item)
    }

    private func finishZeroSFX() {
        guard zeroPlaying else { return }
        zeroPlaying = false
        drainZeroWaiters()
    }

    private func drainZeroWaiters() {
        let waiters = zeroWaiters
        zeroWaiters.removeAll()
        for waiter in waiters { waiter() }
    }

    private func resolvedRemainingSeconds(turnDeadlineAt: String?, turnRemainingSeconds: Double?) -> Double? {
        if let turnRemainingSeconds { return turnRemainingSeconds }
        guard let turnDeadlineAt, let deadline = Self.parseISO8601(turnDeadlineAt) else { return nil }
        return deadline.timeIntervalSinceNow
    }

    private static func parseISO8601(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        return standard.date(from: value)
    }
}
