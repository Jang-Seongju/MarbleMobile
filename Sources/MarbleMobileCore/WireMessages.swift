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

    public static func roomManagementUpdate(_ request: RoomManagementRequest) -> [String: Any] {
        [
            "type": "room_management_update",
            "title": request.title,
            "max_players": request.maxPlayers,
            "is_private": request.isPrivate,
            "password": request.password.map { $0 as Any } ?? NSNull(),
        ]
    }

    public static func roomKick(targetUserID: Int) -> [String: Any] {
        ["type": "room_kick", "target_user_id": targetUserID]
    }

    public static func getSpectatorTargets(roomID: Int) -> [String: Any] {
        ["type": "get_spectator_targets", "room_id": roomID]
    }

    public static func joinSpectator(
        roomID: Int,
        observedUserID: Int,
        password: String? = nil
    ) -> [String: Any] {
        var message: [String: Any] = [
            "type": "join_spectator",
            "room_id": roomID,
            "observed_user_id": observedUserID,
        ]
        if let password {
            let trimmed = password.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { message["password"] = password }
        }
        return message
    }

    public static func leaveSpectator() -> [String: Any] {
        ["type": "leave_spectator"]
    }

    public static func joinRoomFromSpectator() -> [String: Any] {
        ["type": "join_room_from_spectator"]
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

    public static func privateChat(targetUserID: Int, message: String) -> [String: Any] {
        ["type": "chat", "target_id": targetUserID, "message": message]
    }

    public static func noteMailboxGet() -> [String: Any] {
        ["type": "note_mailbox_get"]
    }

    public static func noteSend(targetUserID: Int, body: String) -> [String: Any] {
        ["type": "note_send", "target_user_id": targetUserID, "body": body]
    }

    public static func noteMarkRead(noteID: Int) -> [String: Any] {
        ["type": "note_mark_read", "note_id": noteID]
    }

    public static func noteRecall(noteID: Int) -> [String: Any] {
        ["type": "note_recall", "note_id": noteID]
    }

    public static func noteRecipientSearch(query: String) -> [String: Any] {
        ["type": "note_recipient_search", "query": query.trimmingCharacters(in: .whitespacesAndNewlines)]
    }

    public static func noteDelete(noteID: Int) -> [String: Any] {
        ["type": "note_delete", "note_id": noteID]
    }

    public static func noteDeleteConversation(targetUserID: Int) -> [String: Any] {
        ["type": "note_delete_conversation", "target_user_id": targetUserID]
    }

    public static func friendRequestMarkRead(requestID: Int) -> [String: Any] {
        ["type": "friend_request_mark_read", "request_id": requestID]
    }

    public static func friendRequestReject(requestID: Int) -> [String: Any] {
        ["type": "friend_request_reject", "request_id": requestID]
    }

    public static func invitationSend(targetUserID: Int, inviteType: String) -> [String: Any] {
        ["type": "invitation_send", "target_user_id": targetUserID, "invite_type": inviteType]
    }

    public static func invitationSend(targetUserID: Int, inviteType: GameInvitationType) -> [String: Any] {
        invitationSend(targetUserID: targetUserID, inviteType: inviteType.rawValue)
    }

    public static func invitationAccept(inviteID: Int) -> [String: Any] {
        ["type": "invitation_accept", "invite_id": inviteID]
    }

    public static func socialSearchUsers(query: String) -> [String: Any] {
        ["type": "social_search_users", "query": query]
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

    public static func gameRecoveryCompleted(recoveryID: String) -> [String: Any] {
        ["type": "game_recovery_completed", "recovery_id": recoveryID]
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
