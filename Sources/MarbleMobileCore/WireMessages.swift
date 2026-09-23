import Foundation

public enum WireMessages {

    public static func createRoom(_ request: RoomCreationRequest) -> [String: Any] {
        var message: [String: Any] = [
            "type": "create_room",
            "title": request.title,
            "max_players": request.maxPlayers,
            "is_private": request.isPrivate,
        ]
        if let password = request.password {
            message["password"] = password
        }
        return message
    }
    public static func socialGetState() -> [String: Any] {
        ["type": "social_get_state"]
    }

    public static func invitationSend(targetUserID: Int, inviteType: String) -> [String: Any] {
        ["type": "invitation_send", "target_user_id": targetUserID, "invite_type": inviteType]
    }

    public static func friendRequestSend(targetUserID: Int) -> [String: Any] {
        ["type": "friend_request_send", "target_user_id": targetUserID]
    }

    public static func friendRequestAccept(requestID: Int) -> [String: Any] {
        ["type": "friend_request_accept", "request_id": requestID]
    }

    public static func friendRequestCancel(requestID: Int) -> [String: Any] {
        ["type": "friend_request_cancel", "request_id": requestID]
    }

    public static func friendshipUnfriend(targetUserID: Int) -> [String: Any] {
        ["type": "friendship_unfriend", "target_user_id": targetUserID]
    }

    public static func userBlock(targetUserID: Int) -> [String: Any] {
        ["type": "user_block", "target_user_id": targetUserID]
    }

    public static func userUnblock(targetUserID: Int) -> [String: Any] {
        ["type": "user_unblock", "target_user_id": targetUserID]
    }
}
