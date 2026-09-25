import SwiftUI
import UIKit

/// VoiceOver Direct Touch가 활성인 동안 보드 제스처를 앱에 직접 전달하는 표면.
/// 게임 의미는 판단하지 않고 AppModel의 공통 정보/로터 경계로 입력만 전달한다.
struct GameBoardDirectTouchSurface: UIViewRepresentable {
    let currentCellDescription: String
    let onPreviousCell: () -> Void
    let onNextCell: () -> Void
    let onPreviousCityCost: () -> Void
    let onNextCityCost: () -> Void
    let onExitDirectTouch: () -> Void
    let onMagicTap: () -> Void
    let onEscape: () -> Void
    let onSelectedPlayerInfo: () -> Void
    let onRotorForward: () -> Void
    let onRotorBackward: () -> Void
    let onPreviousRotorSelection: () -> Void
    let onNextRotorSelection: () -> Void
    let onPreviousRotorDetail: () -> Void
    let onNextRotorDetail: () -> Void
    let onLineA: () -> Void
    let onLineB: () -> Void
    let onLineC: () -> Void
    let onLineD: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> DirectTouchBoardView {
        let view = DirectTouchBoardView(frame: .zero)
        view.backgroundColor = .clear
        view.isAccessibilityElement = true
        view.accessibilityLabel = "게임 보드"
        view.accessibilityHint = "한 손가락 좌우로 보드 칸을 이동하고 아래와 위로 현재 도시 비용을 순환합니다. 두 손가락 회전으로 게임 로터를 바꾸고, 두 손가락 좌우로 로터 선택을 바꾸며, 아래와 위로 세부 정보를 순환합니다. 세 손가락 방향 쓸기로 라인을 이동하고 세 손가락 두 번 탭으로 선택된 플레이어 정보를 조회합니다. 한 손가락 두 번 탭하면 표준 VoiceOver로 돌아갑니다."
        view.accessibilityTraits = [.allowsDirectInteraction]
        view.accessibilityDirectTouchOptions = .silentOnTouch
        view.callbacks = context.coordinator.callbacks

        // PC판 보드 탐색 방향: 왼쪽은 다음 칸(출발지 → 방콕), 오른쪽은 이전 칸(출발지 → 서울).
        addSwipe(.left, touches: 1, selector: #selector(Coordinator.nextCell), to: view, coordinator: context.coordinator)
        addSwipe(.right, touches: 1, selector: #selector(Coordinator.previousCell), to: view, coordinator: context.coordinator)
        addSwipe(.up, touches: 1, selector: #selector(Coordinator.previousCityCost), to: view, coordinator: context.coordinator)
        addSwipe(.down, touches: 1, selector: #selector(Coordinator.nextCityCost), to: view, coordinator: context.coordinator)

        // 앱 소유 Game Rotor. 좌/우는 하위 선택, 아래/위는 다음/이전 세부 항목.
        addSwipe(.left, touches: 2, selector: #selector(Coordinator.twoFingerSwipe(_:)), to: view, coordinator: context.coordinator)
        addSwipe(.right, touches: 2, selector: #selector(Coordinator.twoFingerSwipe(_:)), to: view, coordinator: context.coordinator)
        addSwipe(.up, touches: 2, selector: #selector(Coordinator.twoFingerSwipe(_:)), to: view, coordinator: context.coordinator)
        addSwipe(.down, touches: 2, selector: #selector(Coordinator.twoFingerSwipe(_:)), to: view, coordinator: context.coordinator)

        let rotorRotation = UIRotationGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.gameRotorRotated(_:)))
        rotorRotation.delegate = context.coordinator
        view.addGestureRecognizer(rotorRotation)

        // 확정된 절대 라인 이동: 왼쪽=B, 오른쪽=D, 위=C, 아래=A.
        addSwipe(.left, touches: 3, selector: #selector(Coordinator.lineB), to: view, coordinator: context.coordinator)
        addSwipe(.right, touches: 3, selector: #selector(Coordinator.lineD), to: view, coordinator: context.coordinator)
        addSwipe(.up, touches: 3, selector: #selector(Coordinator.lineC), to: view, coordinator: context.coordinator)
        addSwipe(.down, touches: 3, selector: #selector(Coordinator.lineA), to: view, coordinator: context.coordinator)

        let exitTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.exitDirectTouch))
        exitTap.numberOfTouchesRequired = 1
        exitTap.numberOfTapsRequired = 2
        view.addGestureRecognizer(exitTap)

        let magicTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.magicTap(_:)))
        magicTap.numberOfTouchesRequired = 2
        magicTap.numberOfTapsRequired = 2
        view.addGestureRecognizer(magicTap)

        let playerInfoTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.selectedPlayerInfo))
        playerInfoTap.numberOfTouchesRequired = 3
        playerInfoTap.numberOfTapsRequired = 2
        view.addGestureRecognizer(playerInfoTap)

        return view
    }

    func updateUIView(_ uiView: DirectTouchBoardView, context: Context) {
        context.coordinator.parent = self
        uiView.callbacks = context.coordinator.callbacks
        uiView.accessibilityValue = currentCellDescription
    }

    private func addSwipe(
        _ direction: UISwipeGestureRecognizer.Direction,
        touches: Int,
        selector: Selector,
        to view: UIView,
        coordinator: Coordinator
    ) {
        let recognizer = UISwipeGestureRecognizer(target: coordinator, action: selector)
        recognizer.direction = direction
        recognizer.numberOfTouchesRequired = touches
        if touches == 2 { recognizer.delegate = coordinator }
        view.addGestureRecognizer(recognizer)
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        enum TwoFingerWinner { case swipe, rotation }

        var parent: GameBoardDirectTouchSurface
        private var twoFingerWinner: TwoFingerWinner?
        private let rotorThreshold: CGFloat = .pi / 10

        init(parent: GameBoardDirectTouchSurface) {
            self.parent = parent
        }

        var callbacks: DirectTouchBoardView.Callbacks {
            .init(onMagicTap: parent.onMagicTap, onEscape: parent.onEscape)
        }

        @objc func previousCell() { parent.onPreviousCell() }
        @objc func nextCell() { parent.onNextCell() }
        @objc func previousCityCost() { parent.onPreviousCityCost() }
        @objc func nextCityCost() { parent.onNextCityCost() }
        @objc func exitDirectTouch() { parent.onExitDirectTouch() }
        @objc func selectedPlayerInfo() { parent.onSelectedPlayerInfo() }
        @objc func lineA() { parent.onLineA() }
        @objc func lineB() { parent.onLineB() }
        @objc func lineC() { parent.onLineC() }
        @objc func lineD() { parent.onLineD() }

        @objc func twoFingerSwipe(_ recognizer: UISwipeGestureRecognizer) {
            guard twoFingerWinner != .rotation else { return }
            twoFingerWinner = .swipe
            switch recognizer.direction {
            case .left: parent.onPreviousRotorSelection()
            case .right: parent.onNextRotorSelection()
            case .up: parent.onPreviousRotorDetail()
            case .down: parent.onNextRotorDetail()
            default: break
            }
            DispatchQueue.main.async { [weak self] in
                guard self?.twoFingerWinner == .swipe else { return }
                self?.twoFingerWinner = nil
            }
        }

        @objc func gameRotorRotated(_ recognizer: UIRotationGestureRecognizer) {
            switch recognizer.state {
            case .changed:
                if twoFingerWinner == nil, abs(recognizer.rotation) >= rotorThreshold {
                    twoFingerWinner = .rotation
                }
            case .ended:
                defer { twoFingerWinner = nil }
                guard twoFingerWinner == .rotation, abs(recognizer.rotation) >= rotorThreshold else { return }
                // UIKit 좌표계에서 양의 rotation을 다음 로터 범주로 사용한다.
                if recognizer.rotation > 0 { parent.onRotorForward() }
                else { parent.onRotorBackward() }
            case .cancelled, .failed:
                if twoFingerWinner == .rotation { twoFingerWinner = nil }
            default:
                break
            }
        }

        @objc func magicTap(_ recognizer: UITapGestureRecognizer) {
            (recognizer.view as? DirectTouchBoardView)?.performMagicTapOnce()
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            let pair = [gestureRecognizer, otherGestureRecognizer]
            let hasRotation = pair.contains { $0 is UIRotationGestureRecognizer }
            let hasTwoFingerSwipe = pair.contains {
                guard let swipe = $0 as? UISwipeGestureRecognizer else { return false }
                return swipe.numberOfTouchesRequired == 2
            }
            return hasRotation && hasTwoFingerSwipe
        }
    }
}

final class DirectTouchBoardView: UIView {
    struct Callbacks {
        let onMagicTap: () -> Void
        let onEscape: () -> Void
    }

    var callbacks: Callbacks?
    private var lastMagicTapTime: CFTimeInterval = 0

    override func accessibilityPerformMagicTap() -> Bool {
        performMagicTapOnce()
        return true
    }

    override func accessibilityPerformEscape() -> Bool {
        callbacks?.onEscape()
        return true
    }

    func performMagicTapOnce() {
        let now = CACurrentMediaTime()
        guard now - lastMagicTapTime > 0.25 else { return }
        lastMagicTapTime = now
        callbacks?.onMagicTap()
    }
}
