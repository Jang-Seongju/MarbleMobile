import Foundation

public enum MainMenuCommand: String, Identifiable, Sendable {
    case login
    case logout
    case notes
    case friends
    case ranking
    case gameRecords
    case exit
    case leaveRoom

    case startGame
    case showLobby
    case participateRoom
    case roomInfo
    case myProfile
    case roomManagement

    case mediaManagement
    case receiveSettings

    public var id: String { rawValue }
}

public enum MainMenuSectionKind: String, Identifiable, Sendable {
    case file
    case action
    case settings

    public var id: String { rawValue }
}

public struct MainMenuSectionDefinition: Identifiable, Equatable, Sendable {
    public let kind: MainMenuSectionKind
    public let title: String
    public let groups: [[MainMenuCommand]]

    public var id: MainMenuSectionKind { kind }

    public init(kind: MainMenuSectionKind, title: String, groups: [[MainMenuCommand]]) {
        self.kind = kind
        self.title = title
        self.groups = groups
    }
}

/// client(393) app/ui/main_menu.py의 구조/순서/표시명을 모바일 공통 메뉴의
/// 단일 원천으로 옮긴다. PC 전용 핫키/단축키 표시는 의도적으로 포함하지 않는다.
public enum MainMenuDefinition {
    public static let sections: [MainMenuSectionDefinition] = [
        .init(
            kind: .file,
            title: "파일",
            groups: [
                [.login, .logout],
                [.notes, .friends, .ranking, .gameRecords],
                [.exit, .leaveRoom],
            ]
        ),
        .init(
            kind: .action,
            title: "동작",
            groups: [
                [.startGame, .showLobby, .participateRoom, .roomInfo, .myProfile, .roomManagement],
            ]
        ),
        .init(
            kind: .settings,
            title: "설정",
            groups: [
                [.mediaManagement],
                [.receiveSettings],
            ]
        ),
    ]

    public static func title(for command: MainMenuCommand) -> String {
        switch command {
        case .login: return "로그인"
        case .logout: return "로그아웃"
        case .notes: return "쪽지함"
        case .friends: return "친구 관리"
        case .ranking: return "순위 보기"
        case .gameRecords: return "게임 기록"
        case .exit: return "종료"
        case .leaveRoom: return "퇴장"
        case .startGame: return "게임 시작"
        case .showLobby: return "대기실 열기"
        case .participateRoom: return "게임방 입장"
        case .roomInfo: return "방 정보"
        case .myProfile: return "내 정보"
        case .roomManagement: return "방 관리"
        case .mediaManagement: return "미디어 관리"
        case .receiveSettings: return "수신 설정"
        }
    }
}
