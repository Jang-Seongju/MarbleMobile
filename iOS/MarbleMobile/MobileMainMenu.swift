import SwiftUI
import MarbleMobileCore

enum MobileMainMenuContext {
    case login
    case lobby
    case gameRoom
}

/// client(393)의 공통 메뉴 구조를 그대로 표시하고, 모바일에서 아직 이식되지 않은
/// 기능은 위치를 보존한 채 비활성화한다. 기능을 추가할 때 메뉴를 삽입하지 않고
/// 기존 command의 enabled/action만 연결하는 것이 원칙이다.
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
        }
    }

    private func isEnabled(_ command: MainMenuCommand) -> Bool {
        switch context {
        case .login:
            switch command {
            case .login:
                return loginEnabled && onLogin != nil
            // iOS에는 PC판의 애플리케이션 종료 명령을 직접 대응시키지 않는다.
            // 미디어 관리 역시 아직 모바일 UI가 없으므로 골격만 노출한다.
            default:
                return false
            }

        case .lobby:
            switch command {
            case .logout:
                return model.session != nil
            case .roomInfo:
                return model.entryPhase == .active
            case .myProfile:
                return model.entryPhase == .active && model.session != nil
            // 쪽지함/친구 관리/순위/게임 기록/미디어/수신 설정과 관전자 전환은
            // 후속 PC 기능 이식 단계에서 이 command 자리를 그대로 활성화한다.
            default:
                return false
            }

        case .gameRoom:
            switch command {
            case .logout:
                return model.session != nil
            case .leaveRoom:
                return onLeaveRoom != nil && model.canLeaveRoom
            case .startGame:
                return model.canRequestGameStart
            case .showLobby:
                return model.entryPhase == .active && model.roomEntry != nil
            // 현재 게임방에서의 방 정보/내 정보 창, 방 관리 및 나머지 부가기능은
            // 후속 이식 단계에서 연결한다.
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
        case .roomInfo:
            guard let room = selectedLobbyRoom else {
                model.alertMessage = "방을 선택해 주세요."
                return
            }
            model.performRoomAction(.roomInfo, room: room)
        case .myProfile:
            model.openMyProfile()
        case .notes, .friends, .ranking, .gameRecords, .exit,
             .participateRoom, .roomManagement, .mediaManagement, .receiveSettings:
            break
        }
    }
}
