import SwiftUI
import MarbleMobileCore

struct FriendManagementView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @AccessibilityFocusState private var focusedRequestID: Int?

    var body: some View {
        NavigationStack {
            List {
                Section("받은 요청") {
                    if model.socialState.incomingRequests.isEmpty {
                        Text("항목 없음")
                    } else {
                        ForEach(model.socialState.incomingRequests, id: \.requestID) { request in
                            VStack(alignment: .leading) {
                                Text(request.user.nickname)
                                    .accessibilityFocused($focusedRequestID, equals: request.requestID)
                                HStack {
                                    Button("수락") { model.acceptFriendRequest(request.requestID) }
                                    Button("거절") { model.rejectFriendRequest(request.requestID) }
                                    Button("메시지") { model.openPrivateConversation(userID: request.user.userID, nickname: request.user.nickname) }
                                }
                            }
                        }
                    }
                }
                Section("친구") {
                    if model.socialState.friends.isEmpty { Text("항목 없음") }
                    ForEach(model.socialState.friends, id: \.userID) { user in
                        VStack(alignment: .leading) {
                            Text(user.nickname)
                            HStack {
                                Button("메시지") { model.openPrivateConversation(userID: user.userID, nickname: user.nickname) }
                                Button("쪽지") { model.openNoteMailbox(targetUser: user) }
                            }
                        }
                    }
                }
                Section("보낸 요청") {
                    if model.socialState.outgoingRequests.isEmpty { Text("항목 없음") }
                    ForEach(model.socialState.outgoingRequests, id: \.requestID) { request in
                        HStack {
                            Text(request.user.nickname)
                            Button("요청 취소") { model.cancelFriendRequest(request.requestID) }
                        }
                    }
                }
                Section("차단") {
                    if model.socialState.blockedUsers.isEmpty { Text("항목 없음") }
                    ForEach(model.socialState.blockedUsers, id: \.userID) { user in
                        HStack {
                            Text(user.nickname)
                            Button("차단 해제") { model.unblockUser(user.userID) }
                        }
                    }
                }
            }
            .navigationTitle("친구 관리")
            .onChange(of: focusedRequestID) { _, requestID in
                if let requestID { model.markFriendRequestRead(requestID) }
            }
            .onAppear { model.requestSocialState() }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("닫기") { dismiss() }
                }
            }
        }
    }
}
