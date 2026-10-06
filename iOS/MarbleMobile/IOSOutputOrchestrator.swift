import Foundation
import MarbleMobileCore

@MainActor
final class IOSOutputOrchestrator {
    var noticeSink: ((String) -> Void)?

    private struct QueuedPlan {
        let plan: PresentationPlan
        let gameplayAudioSuppressed: Bool
    }

    private enum PendingItem {
        case plan(QueuedPlan)
        case barrier((@escaping () -> Void) -> Void)
    }

    private let audio: IOSAudioController
    private let voiceOver = VoiceOverAnnouncementQueue()
    private var pending: [PendingItem] = []
    private var isExecuting = false
    private var executingBarrier = false
    private var generation = 0
    // client(393)의 future GAMEPLAY audio policy와 같은 emit-time snapshot.
    // 이미 큐에 들어간 마지막 인간 턴 출력은 이 값 변경의 영향을 받지 않는다.
    private var futureGameplayAudioSuppressed = false

    init(audio: IOSAudioController? = nil) {
        self.audio = audio ?? IOSAudioController()
    }

    func emit(_ plan: PresentationPlan) {
        MobileDiagnosticLog.shared.record(
            "OUTPUT_ENQUEUE",
            "category=\(plan.category.rawValue) policy=\(plan.queuePolicy.rawValue) pending_before=\(pending.count) detail=\(Self.describeForLog(plan))"
        )
        if let notice = plan.persistentNotice, !notice.isEmpty {
            noticeSink?(notice)
        }

        let queued = QueuedPlan(
            plan: plan,
            gameplayAudioSuppressed: plan.category == .gameplay && futureGameplayAudioSuppressed
        )
        switch plan.queuePolicy {
        case .enqueue:
            pending.append(.plan(queued))
        case .interrupt:
            interruptCurrent(retention: .preserveMarkedPlansAndBarriers)
            pending.insert(.plan(queued), at: 0)
        case .userInputInterrupt:
            interruptCurrent(retention: .preserveAllPending)
            pending.insert(.plan(queued), at: 0)
        }
        startNextIfNeeded()
    }

    /// PC OutputOrchestrator.enqueue_barrier()와 같은 ordering boundary.
    /// 등록 시점 이전 출력이 모두 끝난 뒤, 다음 plan보다 먼저 callback을 실행한다.
    func enqueueBarrier(_ callback: @escaping () -> Void) {
        enqueueAsyncBarrier { completion in
            callback()
            completion()
        }
    }

    /// 완료 시점을 외부 playback이 결정하는 ordering barrier.
    /// 턴 0초 경고 SFX처럼 presentation queue 밖의 전용 오디오도 다음 턴 출력보다
    /// 먼저 자연스럽게 끝나도록 직렬화할 때 사용한다.
    func enqueueAsyncBarrier(_ callback: @escaping (@escaping () -> Void) -> Void) {
        pending.append(.barrier(callback))
        startNextIfNeeded()
    }

    func stopAll() {
        MobileDiagnosticLog.shared.record("OUTPUT", "stopAll pending=\(pending.count) executing=\(isExecuting) generation=\(generation)")
        generation += 1
        pending.removeAll()
        isExecuting = false
        executingBarrier = false
        voiceOver.cancelCurrent()
        audio.stopAll()
    }

    /// Spectator catch-up boundary. Drop only transient/pending presentation output while
    /// preserving persistent scene BGM. Any completion from the old generation is ignored.
    @discardableResult
    func discardTransientBacklogForSpectatorSync() -> Int {
        let dropped = pending.count + (isExecuting ? 1 : 0)
        MobileDiagnosticLog.shared.record(
            "OUTPUT_SYNC",
            "discard transient backlog dropped=\(dropped) generation=\(generation)->\(generation + 1)"
        )
        generation += 1
        pending.removeAll()
        isExecuting = false
        executingBarrier = false
        voiceOver.cancelCurrent()
        audio.stopTransient()
        return dropped
    }

    func stopBGM() { audio.stopBGM() }

    @discardableResult
    func setFutureGameplayAudioSuppressed(_ suppressed: Bool) -> Bool {
        futureGameplayAudioSuppressed = suppressed
        return true
    }

    private enum PendingRetention {
        case preserveMarkedPlansAndBarriers
        case preserveAllPending
    }

    private func interruptCurrent(retention: PendingRetention) {
        // Ordering barrier는 PC판과 마찬가지로 interrupt 보호 구간이다. barrier가
        // 실행 중이면 queued policy만 갱신하고 barrier 완료 뒤 새 plan을 실행한다.
        if !executingBarrier {
            generation += 1
            isExecuting = false
        }
        voiceOver.cancelCurrent()
        audio.stopTransient()
        switch retention {
        case .preserveMarkedPlansAndBarriers:
            pending = pending.filter { item in
                switch item {
                case .barrier: return true
                case .plan(let queued): return queued.plan.interruptRetention == .preservePending
                }
            }
        case .preserveAllPending:
            break
        }
    }

    private func startNextIfNeeded() {
        guard !isExecuting, !pending.isEmpty else { return }
        isExecuting = true
        let item = pending.removeFirst()
        switch item {
        case .barrier(let callback):
            MobileDiagnosticLog.shared.record("OUTPUT_START", "barrier pending_after_pop=\(pending.count) generation=\(generation)")
            executingBarrier = true
            let token = generation
            callback { [weak self] in
                guard let self, self.generation == token else { return }
                MobileDiagnosticLog.shared.record("OUTPUT_DONE", "barrier generation=\(token)")
                self.executingBarrier = false
                self.isExecuting = false
                self.startNextIfNeeded()
            }

        case .plan(let queued):
            MobileDiagnosticLog.shared.record(
                "OUTPUT_START",
                "category=\(queued.plan.category.rawValue) pending_after_pop=\(pending.count) generation=\(generation) detail=\(Self.describeForLog(queued.plan))"
            )
            let token = generation
            execute(
                queued.plan.root,
                token: token,
                gameplayAudioSuppressed: queued.gameplayAudioSuppressed
            ) { [weak self] in
                guard let self, self.generation == token else { return }
                MobileDiagnosticLog.shared.record(
                    "OUTPUT_DONE",
                    "category=\(queued.plan.category.rawValue) generation=\(token) detail=\(Self.describeForLog(queued.plan))"
                )
                self.isExecuting = false
                self.startNextIfNeeded()
            }
        }
    }

    private func execute(
        _ node: PresentationNode,
        token: Int,
        gameplayAudioSuppressed: Bool = false,
        completion: @escaping () -> Void
    ) {
        guard token == generation else { return }
        switch node {
        case .tts(let text):
            if gameplayAudioSuppressed { completion(); return }
            voiceOver.speak(text) { [weak self] in
                guard let self, self.generation == token else { return }
                completion()
            }

        case .voice(let clip, let fallbackTTS):
            if gameplayAudioSuppressed { completion(); return }
            var started = false
            started = audio.playVoice(clip) { [weak self] success in
                guard let self, self.generation == token else { return }
                if success || fallbackTTS == nil || !self.audio.settings.sfxEnabled {
                    completion()
                } else if let fallbackTTS {
                    self.voiceOver.speak(fallbackTTS, completion: completion)
                }
            }
            if !started {
                if let fallbackTTS, audio.settings.sfxEnabled {
                    voiceOver.speak(fallbackTTS, completion: completion)
                } else {
                    completion()
                }
            }

        case .sfx(let clip, let policy):
            if gameplayAudioSuppressed { completion(); return }
            if policy == .startOnly {
                _ = audio.playSFX(clip)
                completion()
            } else {
                let started = audio.playSFX(clip) { [weak self] _ in
                    guard let self, self.generation == token else { return }
                    completion()
                }
                if !started { completion() }
            }

        case .bgmPlay(let clip, let loop):
            audio.playBGM(clip, loop: loop)
            completion()

        case .bgmStop:
            audio.stopBGM()
            completion()

        case .delay(let milliseconds):
            if gameplayAudioSuppressed { completion(); return }
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(max(0, milliseconds))) { [weak self] in
                guard let self, self.generation == token else { return }
                completion()
            }

        case .sequence(let children):
            executeSequence(
                children,
                index: 0,
                token: token,
                gameplayAudioSuppressed: gameplayAudioSuppressed,
                completion: completion
            )

        case .parallel(let children):
            guard !children.isEmpty else { completion(); return }
            var remaining = children.count
            for child in children {
                execute(child, token: token, gameplayAudioSuppressed: gameplayAudioSuppressed) { [weak self] in
                    guard let self, self.generation == token else { return }
                    remaining -= 1
                    if remaining == 0 { completion() }
                }
            }
        }
    }

    private func executeSequence(
        _ children: [PresentationNode],
        index: Int,
        token: Int,
        gameplayAudioSuppressed: Bool,
        completion: @escaping () -> Void
    ) {
        guard token == generation else { return }
        guard index < children.count else { completion(); return }
        execute(children[index], token: token, gameplayAudioSuppressed: gameplayAudioSuppressed) { [weak self] in
            guard let self, self.generation == token else { return }
            self.executeSequence(
                children,
                index: index + 1,
                token: token,
                gameplayAudioSuppressed: gameplayAudioSuppressed,
                completion: completion
            )
        }
    }

    private static func describeForLog(_ plan: PresentationPlan) -> String {
        let root = describeNode(plan.root)
        guard plan.category == .gameplay,
              let notice = plan.persistentNotice, !notice.isEmpty else { return root }
        return "notice=\(String(notice.prefix(240))) root=\(root)"
    }

    private static func describeNode(_ node: PresentationNode) -> String {
        switch node {
        case .tts(let text):
            return "tts(length=\(text.count))"
        case .voice(let clip, let fallbackTTS):
            return "voice(\(clip),fallback=\(fallbackTTS != nil))"
        case .sfx(let clip, let policy):
            return "sfx(\(clip),\(policy.rawValue))"
        case .bgmPlay(let clip, let loop):
            return "bgmPlay(\(clip),loop=\(loop))"
        case .bgmStop:
            return "bgmStop"
        case .delay(let milliseconds):
            return "delay(\(milliseconds)ms)"
        case .sequence(let children):
            return "sequence(\(children.prefix(4).map(describeNode).joined(separator: ",")))"
        case .parallel(let children):
            return "parallel(\(children.prefix(4).map(describeNode).joined(separator: ",")))"
        }
    }

}
