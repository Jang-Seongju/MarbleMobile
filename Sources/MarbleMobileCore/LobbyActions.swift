import Foundation

public enum LobbyUserActionKind: String, Identifiable, Sendable {
    case message, note, roomInvite, spectatorInvite
    case friendRequest, friendAccept, friendCancel, unfriend
    case block, unblock, profile
    public var id: String { rawValue }
}

public struct LobbyUserAction: Identifiable, Equatable, Sendable {
    public let kind: LobbyUserActionKind
    public let title: String
    public let isEnabled: Bool
    public var id: String { kind.id }
    public init(kind: LobbyUserActionKind, title: String, isEnabled: Bool = true) {
        self.kind = kind; self.title = title; self.isEnabled = isEnabled
    }
}

public enum LobbyRoomActionKind: String, Identifiable, Sendable {
    case create, join, spectatorEntry, sort, roomInfo
    public var id: String { rawValue }
}

public struct LobbyRoomAction: Identifiable, Equatable, Sendable {
    public let kind: LobbyRoomActionKind
    public let title: String
    public let isEnabled: Bool
    public var id: String { kind.id }
    public init(kind: LobbyRoomActionKind, title: String, isEnabled: Bool = true) {
        self.kind = kind; self.title = title; self.isEnabled = isEnabled
    }
}

public enum LobbyActionBuilder {
    // client(393) _on_user_context_menu()의 순서/조건을 의미 그대로 옮긴다.
    public static func userActions(
        targetUserID: Int,
        currentUserID: Int,
        socialState: SocialState,
        hasGameRoom: Bool,
        isSpectator: Bool,
        messageImplemented: Bool = true,
        noteImplemented: Bool = true,
        roomInvitationImplemented: Bool = true,
        spectatorInvitationImplemented: Bool = true,
        socialInteractionImplemented: Bool = true
    ) -> [LobbyUserAction] {
        let isSelf = targetUserID == currentUserID
        var actions: [LobbyUserAction] = [
            .init(kind: .message, title: "메시지 보내기", isEnabled: messageImplemented),
            .init(kind: .note, title: "쪽지 보내기", isEnabled: !isSelf && noteImplemented),
            .init(
                kind: .roomInvite,
                title: "초대하기",
                isEnabled: !isSelf && hasGameRoom && !isSpectator && roomInvitationImplemented
            ),
            .init(
                kind: .spectatorInvite,
                title: "관중석으로 초대",
                isEnabled: !isSelf && hasGameRoom && spectatorInvitationImplemented
            ),
        ]

        if !isSelf {
            if socialState.isBlocked(targetUserID) {
                actions.append(.init(kind: .unblock, title: "차단 해제", isEnabled: socialInteractionImplemented))
            } else if socialState.isFriend(targetUserID) {
                actions.append(.init(kind: .unfriend, title: "친구 해제", isEnabled: socialInteractionImplemented))
                actions.append(.init(kind: .block, title: "차단", isEnabled: socialInteractionImplemented))
            } else if socialState.incomingRequest(for: targetUserID) != nil {
                actions.append(.init(kind: .friendAccept, title: "친구 요청 수락", isEnabled: socialInteractionImplemented))
                actions.append(.init(kind: .block, title: "차단", isEnabled: socialInteractionImplemented))
            } else if socialState.outgoingRequest(for: targetUserID) != nil {
                actions.append(.init(kind: .friendCancel, title: "요청 취소", isEnabled: socialInteractionImplemented))
                actions.append(.init(kind: .block, title: "차단", isEnabled: socialInteractionImplemented))
            } else {
                actions.append(.init(kind: .friendRequest, title: "친구 요청", isEnabled: socialInteractionImplemented))
                actions.append(.init(kind: .block, title: "차단", isEnabled: socialInteractionImplemented))
            }
        }
        actions.append(.init(kind: .profile, title: "사용자 정보"))
        return actions
    }

    // client(393) _on_room_context_menu()의 순서/조건을 그대로 보존한다.
    public static func roomActions(
        roomCreationImplemented: Bool,
        roomJoinImplemented: Bool,
        spectatorInteractionImplemented: Bool,
        hasRoomTarget: Bool = true
    ) -> [LobbyRoomAction] {
        [
            .init(kind: .create, title: "방 개설", isEnabled: roomCreationImplemented),
            .init(kind: .join, title: "참여하기", isEnabled: hasRoomTarget && roomJoinImplemented),
            .init(kind: .spectatorEntry, title: "관중석 입장", isEnabled: hasRoomTarget && spectatorInteractionImplemented),
            .init(kind: .sort, title: "방 정렬", isEnabled: false),
            .init(kind: .roomInfo, title: "방 정보", isEnabled: hasRoomTarget),
        ]
    }

    public static func roomActions(
        roomInteractionImplemented: Bool,
        spectatorInteractionImplemented: Bool
    ) -> [LobbyRoomAction] {
        roomActions(
            roomCreationImplemented: roomInteractionImplemented,
            roomJoinImplemented: roomInteractionImplemented,
            spectatorInteractionImplemented: spectatorInteractionImplemented
        )
    }
}
