import SwiftUI
import MarbleMobileCore

enum MobileMainMenuContext {
    case login
    case lobby
    case gameRoom
}

/// PC 공통 메뉴의 순서와 항목을 이식한다. iOS 앱 종료는 시스템 앱 전환기가
/// 담당하므로 파일 메뉴의 종료 항목만 제외한다.
struct MobileMainMenu: View {
    @EnvironmentObject private var model: AppModel

    let context: MobileMainMenuContext
    var selectedLobbyRoom: GameRoomSummary?
    var loginEnabled = false
    var onLogin: (() -> Void)?
    var onLeaveRoom: (() -> Void)?

    var body: some View {
        Menu("메뉴") {
            ForEach(MainMenuDefinition.sections) { section in
                Menu(section.title) {
                    ForEach(Array(section.groups.enumerated()), id: \.offset) { index, group in
                        if index > 0 {
                            Divider()
                        }
                        ForEach(group) { command in
                            Button(MainMenuDefinition.title(for: command)) {
                                perform(command)
                            }
                            .disabled(!isEnabled(command))
                        }
                    }
                }
            }
            Divider()
            Button(receiveNotificationTitle) {
                model.presentReceiveNotifications()
            }
            .disabled(context == .login || model.session == nil)
            Button("진단 로그 저장") {
                model.saveDiagnosticLog()
            }
            if context == .gameRoom && model.isSpectating {
                Button("관전 동기화") {
                    model.synchronizeSpectatorOutput()
                }
                .disabled(!model.canSynchronizeSpectatorOutput)
            }
        }
    }


    private var receiveNotificationTitle: String {
        let count = model.receiveNotificationTotalCount
        return count > 0 ? "수신 알림 \(count)" : "수신 알림"
    }

    private func isEnabled(_ command: MainMenuCommand) -> Bool {
        switch context {
        case .login:
            switch command {
            case .login:
                return loginEnabled && onLogin != nil
            case .mediaManagement:
                return true
            default:
                return false
            }

        case .lobby:
            switch command {
            case .logout:
                return model.session != nil
            case .notes, .friends, .ranking, .gameRecords:
                return model.entryPhase == .active
            case .roomInfo:
                return model.entryPhase == .active && selectedLobbyRoom != nil
            case .myProfile:
                return model.entryPhase == .active && model.session != nil
            case .participateRoom:
                return model.canParticipateFromSpectator
            case .mediaManagement:
                return true
            case .receiveSettings:
                return model.canOpenReceiveSettings
            // 나머지 아직 이식되지 않은 명령은 기존 자리를 보존한다.
            default:
                return false
            }

        case .gameRoom:
            if model.isSpectatorParticipationPending { return false }
            switch command {
            case .logout:
                return model.session != nil
            case .leaveRoom:
                return onLeaveRoom != nil && model.canLeaveRoom
            case .startGame:
                return model.canRequestGameStart
            case .showLobby:
                return model.entryPhase == .active && model.isInGameRoom
                    && (!model.isSpectating || model.spectatorPhase == .active)
            case .participateRoom:
                return model.canParticipateFromSpectator
            case .notes, .friends, .ranking, .gameRecords:
                return model.entryPhase == .active
            case .roomInfo:
                return model.entryPhase == .active && model.roomUpdate?.roomID == model.currentRoomID
            case .myProfile:
                return model.entryPhase == .active && model.session != nil
            case .roomManagement:
                return model.canManageRoom
            case .mediaManagement:
                return true
            case .receiveSettings:
                return model.canOpenReceiveSettings
            default:
                return false
            }
        }
    }

    private func perform(_ command: MainMenuCommand) {
        guard isEnabled(command) else { return }

        switch command {
        case .login:
            onLogin?()
        case .logout:
            model.logout()
        case .leaveRoom:
            onLeaveRoom?()
        case .startGame:
            model.requestGameStart()
        case .showLobby:
            model.showLobbyFromGameRoom()
        case .participateRoom:
            model.requestSpectatorParticipation()
        case .roomInfo:
            if context == .gameRoom {
                model.openCurrentRoomInfo()
                return
            }
            guard let room = selectedLobbyRoom else {
                model.alertMessage = "방을 선택해 주세요."
                return
            }
            model.performRoomAction(.roomInfo, room: room)
        case .myProfile:
            model.openMyProfile()
        case .roomManagement:
            model.openRoomManagement()
        case .mediaManagement:
            model.utilitySheet = .mediaManagement
        case .receiveSettings:
            model.openReceiveSettings()
        case .notes:
            model.openNoteMailbox()
        case .friends:
            model.utilitySheet = .friendManagement
        case .ranking:
            model.openRankings()
        case .gameRecords:
            model.openGameRecords()
        }
    }
}
