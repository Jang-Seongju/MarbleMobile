import Foundation

public enum WireMessages {

    public static func createTeam(teamName: String) -> [String: Any] {
        ["type": "create_team", "team_name": teamName]
    }

    public static func roomChat(message: String) -> [String: Any] {
        ["type": "room_chat", "message": message]
    }

    public static func leaveRoom() -> [String: Any] {
        ["type": "leave_room"]
    }

    public static func joinRoom(roomID: Int, password: String? = nil) -> [String: Any] {
        var message: [String: Any] = [
            "type": "join_room",
            "room_id": roomID,
        ]
        if let password {
            let trimmed = password.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                message["password"] = trimmed
            }
        }
        return message
    }

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

    public static func gameStart() -> [String: Any] {
        ["type": "game_start"]
    }

    public static func gameStartAISelectionResponse(requestID: String, selectedAIIDs: [String]) -> [String: Any] {
        [
            "type": "game_start_ai_selection_response",
            "request_id": requestID,
            "selected_ai_ids": selectedAIIDs,
        ]
    }

    public static func gameStartAISelectionCancel(requestID: String) -> [String: Any] {
        ["type": "game_start_ai_selection_cancel", "request_id": requestID]
    }

    public static func turnReady(turnGeneration: Int) -> [String: Any] {
        ["type": "game_action", "action": "turn_ready", "turn_generation": turnGeneration]
    }

    public static func rollDice() -> [String: Any] {
        ["type": "game_action", "action": "roll_dice"]
    }

    public static func toggleBailPayment() -> [String: Any] {
        ["type": "game_action", "action": "toggle_bail_payment"]
    }

    public static func toggleHeldCardUse() -> [String: Any] {
        ["type": "game_action", "action": "toggle_held_card_use"]
    }

    public static func interactionResponse(
        requestID: String,
        responseType: String,
        payload: [String: Any] = [:]
    ) -> [String: Any] {
        [
            "type": "game_action",
            "action": "interaction_response",
            "request_id": requestID,
            "response_type": responseType,
            "payload": payload,
        ]
    }

    public static func interactionPresentationActivate(requestID: String) -> [String: Any] {
        [
            "type": "game_action",
            "action": "interaction_presentation_activate",
            "request_id": requestID,
        ]
    }

    public static func informationQuery(
        queryType: String,
        playerID: Int? = nil,
        cityID: Int? = nil,
        view: String? = nil,
        payload: [String: Any] = [:]
    ) -> [String: Any] {
        var message: [String: Any] = [
            "type": "game_action",
            "action": "information_query",
            "query_type": queryType,
        ]
        if let playerID { message["player_id"] = playerID }
        if let cityID { message["city_id"] = cityID }
        if let view { message["view"] = view }
        for (key, value) in payload { message[key] = value }
        return message
    }
}
