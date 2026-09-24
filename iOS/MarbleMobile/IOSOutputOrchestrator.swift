import Foundation
import MarbleMobileCore

@MainActor
final class IOSOutputOrchestrator {
    var noticeSink: ((String) -> Void)?

    private enum PendingItem {
        case plan(PresentationPlan)
        case barrier((@escaping () -> Void) -> Void)
    }

    private let audio: IOSAudioController
    private let voiceOver = VoiceOverAnnouncementQueue()
    private var pending: [PendingItem] = []
    private var isExecuting = false
    private var executingBarrier = false
    private var generation = 0

    init(audio: IOSAudioController = IOSAudioController()) {
        self.audio = audio
    }

    func emit(_ plan: PresentationPlan) {
        if let notice = plan.persistentNotice, !notice.isEmpty {
            noticeSink?(notice)
        }

        switch plan.queuePolicy {
        case .enqueue:
            pending.append(.plan(plan))
        case .interrupt:
            interruptCurrent(retention: .preserveMarkedPlansAndBarriers)
            pending.insert(.plan(plan), at: 0)
        case .userInputInterrupt:
            interruptCurrent(retention: .preserveAllPending)
            pending.insert(.plan(plan), at: 0)
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
        generation += 1
        pending.removeAll()
        isExecuting = false
        executingBarrier = false
        voiceOver.cancelCurrent()
        audio.stopAll()
    }

    func stopBGM() { audio.stopBGM() }

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
                case .plan(let plan): return plan.interruptRetention == .preservePending
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
            executingBarrier = true
            let token = generation
            callback { [weak self] in
                guard let self, self.generation == token else { return }
                self.executingBarrier = false
                self.isExecuting = false
                self.startNextIfNeeded()
            }

        case .plan(let plan):
            let token = generation
            execute(plan.root, token: token) { [weak self] in
                guard let self, self.generation == token else { return }
                self.isExecuting = false
                self.startNextIfNeeded()
            }
        }
    }

    private func execute(_ node: PresentationNode, token: Int, completion: @escaping () -> Void) {
        guard token == generation else { return }
        switch node {
        case .tts(let text):
            voiceOver.speak(text) { [weak self] in
                guard let self, self.generation == token else { return }
                completion()
            }

        case .voice(let clip, let fallbackTTS):
            var started = false
            started = audio.playVoice(clip) { [weak self] success in
                guard let self, self.generation == token else { return }
                if success || fallbackTTS == nil {
                    completion()
                } else if let fallbackTTS {
                    self.voiceOver.speak(fallbackTTS, completion: completion)
                }
            }
            if !started, fallbackTTS == nil { completion() }

        case .sfx(let clip, let policy):
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
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(max(0, milliseconds))) { [weak self] in
                guard let self, self.generation == token else { return }
                completion()
            }

        case .sequence(let children):
            executeSequence(children, index: 0, token: token, completion: completion)

        case .parallel(let children):
            guard !children.isEmpty else { completion(); return }
            var remaining = children.count
            for child in children {
                execute(child, token: token) { [weak self] in
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
        completion: @escaping () -> Void
    ) {
        guard token == generation else { return }
        guard index < children.count else { completion(); return }
        execute(children[index], token: token) { [weak self] in
            guard let self, self.generation == token else { return }
            self.executeSequence(children, index: index + 1, token: token, completion: completion)
        }
    }
}
