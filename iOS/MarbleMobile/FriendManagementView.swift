import SwiftUI
import MarbleMobileCore

private struct FriendManagementAccessibilityAction: Identifiable {
    let title: String
    let perform: () -> Void
    var id: String { title }
}

struct FriendManagementView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var localSocialConfirmation: SocialConfirmation?
    @AccessibilityFocusState private var focusedFriendUserID: Int?
    @AccessibilityFocusState private var focusedIncomingRequestID: Int?
    @AccessibilityFocusState private var focusedSearchUserID: Int?
    @AccessibilityFocusState private var searchFieldFocused: Bool

    var body: some View {
        NavigationStack {
            List {
                Section("친구") {
                    if model.socialState.friends.isEmpty {
                        Text("항목 없음")
                    } else {
                        ForEach(model.socialState.friends, id: \.userID) { user in
                            Text(SocialPresentationFormatter.friendLabel(user))
                                .accessibilityFocused($focusedFriendUserID, equals: user.userID)
                                .accessibilityActions {
                                    actionButtons(friendActions(for: user))
                                }
                        }
                    }
                }

                Section("보낸 요청") {
                    if model.socialState.outgoingRequests.isEmpty {
                        Text("항목 없음")
                    } else {
                        ForEach(model.socialState.outgoingRequests, id: \.requestID) { request in
                            Text(request.user.nickname)
                                .accessibilityActions {
                                    actionButtons(outgoingActions(for: request))
                                }
                        }
                    }
                }

                Section("받은 요청") {
                    if model.socialState.incomingRequests.isEmpty {
                        Text("항목 없음")
                    } else {
                        ForEach(model.socialState.incomingRequests, id: \.requestID) { request in
                            Text(request.user.nickname)
                                .accessibilityFocused($focusedIncomingRequestID, equals: request.requestID)
                                .accessibilityActions {
                                    actionButtons(incomingActions(for: request))
                                }
                        }
                    }
                }

                Section("차단") {
                    if model.socialState.blockedUsers.isEmpty {
                        Text("항목 없음")
                    } else {
                        ForEach(model.socialState.blockedUsers, id: \.userID) { user in
                            Text(user.nickname)
                                .accessibilityActions {
                                    actionButtons(blockedActions(for: user))
                                }
                        }
                    }
                }

                Section("검색") {
                    TextField("검색", text: $searchText)
                        .submitLabel(.search)
                        .onSubmit(search)
                        .accessibilityFocused($searchFieldFocused)
                }

                Section("검색 결과") {
                    if model.socialState.searchResults.isEmpty {
                        Text("항목 없음")
                    } else {
                        ForEach(model.socialState.searchResults, id: \.userID) { user in
                            Text(SocialPresentationFormatter.friendLabel(user))
                                .accessibilityFocused($focusedSearchUserID, equals: user.userID)
                                .accessibilityActions {
                                    actionButtons(searchActions(for: user))
                                }
                        }
                    }
                }
            }
            .navigationTitle("친구 관리")
            .onAppear {
                model.requestSocialState()
                DispatchQueue.main.async {
                    if let requestID = model.preferredFriendRequestID,
                       model.socialState.incomingRequests.contains(where: { $0.requestID == requestID }) {
                        focusedIncomingRequestID = requestID
                    } else {
                        focusedFriendUserID = model.socialState.friends.first?.userID
                    }
                    model.preferredFriendRequestID = nil
                }
            }
            .onChange(of: focusedIncomingRequestID) { _, requestID in
                if let requestID { model.markFriendRequestRead(requestID) }
            }
            .onChange(of: model.socialState.searchResults) { _, results in
                guard !model.socialState.searchQuery.isEmpty else { return }
                DispatchQueue.main.async {
                    if let first = results.first {
                        focusedSearchUserID = first.userID
                    } else {
                        model.announce("검색 결과가 없습니다.")
                        searchFieldFocused = true
                    }
                }
            }
            .confirmationDialog(
                localSocialConfirmation?.title ?? "확인",
                isPresented: Binding(
                    get: { localSocialConfirmation != nil },
                    set: { if !$0 { localSocialConfirmation = nil } }
                ),
                titleVisibility: .visible
            ) {
                if let confirmation = localSocialConfirmation {
                    Button("예", role: .destructive) {
                        model.confirmSocialAction(confirmation)
                        localSocialConfirmation = nil
                    }
                }
                Button("아니오", role: .cancel) { localSocialConfirmation = nil }
            } message: {
                Text(localSocialConfirmation?.message ?? "")
            }
            .sheet(isPresented: Binding(
                get: { model.profileText != nil },
                set: { if !$0 { model.profileText = nil } }
            )) {
                InformationDocumentView(
                    title: "정보",
                    lines: PresentationFormatter.profileLines(model.profileText ?? ""),
                    onClose: { model.profileText = nil }
                )
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("닫기") { dismiss() }
                }
            }
        }
    }

    private func search() {
        model.searchSocialUsers(searchText)
    }

    private func lobbyUser(_ user: SocialUser) -> LobbyUser {
        LobbyUser(
            id: user.userID,
            nickname: user.nickname,
            connectionStatus: user.connectionStatus,
            isGameInProgress: user.isGameInProgress
        )
    }

    private func friendActions(for user: SocialUser) -> [FriendManagementAccessibilityAction] {
        var result: [FriendManagementAccessibilityAction] = []
        if user.connectionStatus == .connected {
            result.append(.init(title: "메시지 보내기") {
                model.performUserAction(.message, user: lobbyUser(user))
            })
        }
        result.append(.init(title: "쪽지 보내기") {
            model.openNoteMailbox(targetUser: user)
        })
        result.append(.init(title: "친구 해제") {
            requestUnfriend(user)
        })
        result.append(.init(title: "차단") {
            requestBlock(user)
        })
        result.append(.init(title: "사용자 정보") {
            model.performUserAction(.profile, user: lobbyUser(user))
        })
        return result
    }

    private func outgoingActions(for request: FriendRequest) -> [FriendManagementAccessibilityAction] {
        let user = request.user
        return [
            .init(title: "취소") { model.cancelFriendRequest(request.requestID) },
            .init(title: "쪽지 보내기") { model.openNoteMailbox(targetUser: user) },
            .init(title: "사용자 정보") { model.performUserAction(.profile, user: lobbyUser(user)) },
        ]
    }

    private func incomingActions(for request: FriendRequest) -> [FriendManagementAccessibilityAction] {
        let user = request.user
        return [
            .init(title: "수락") { model.acceptFriendRequest(request.requestID) },
            .init(title: "거절") { model.rejectFriendRequest(request.requestID) },
            .init(title: "차단") { requestBlock(user) },
            .init(title: "쪽지 보내기") { model.openNoteMailbox(targetUser: user) },
            .init(title: "사용자 정보") { model.performUserAction(.profile, user: lobbyUser(user)) },
        ]
    }

    private func blockedActions(for user: SocialUser) -> [FriendManagementAccessibilityAction] {
        [
            .init(title: "차단 해제") { model.unblockUser(user.userID) },
            .init(title: "사용자 정보") { model.performUserAction(.profile, user: lobbyUser(user)) },
        ]
    }

    private func searchActions(for user: SocialUser) -> [FriendManagementAccessibilityAction] {
        var result: [FriendManagementAccessibilityAction] = []
        if model.socialState.isBlocked(user.userID) {
            result.append(.init(title: "차단 해제") { model.unblockUser(user.userID) })
        } else if model.socialState.isFriend(user.userID) {
            result.append(.init(title: "친구 해제") {
                requestUnfriend(user)
            })
            result.append(.init(title: "차단") {
                requestBlock(user)
            })
        } else if let incoming = model.socialState.incomingRequest(for: user.userID) {
            result.append(.init(title: "수락") { model.acceptFriendRequest(incoming.requestID) })
            result.append(.init(title: "거절") { model.rejectFriendRequest(incoming.requestID) })
            result.append(.init(title: "차단") {
                requestBlock(user)
            })
        } else if let outgoing = model.socialState.outgoingRequest(for: user.userID) {
            result.append(.init(title: "취소") { model.cancelFriendRequest(outgoing.requestID) })
            result.append(.init(title: "차단") {
                requestBlock(user)
            })
        } else {
            result.append(.init(title: "친구 요청") {
                model.performUserAction(.friendRequest, user: lobbyUser(user))
            })
            result.append(.init(title: "차단") {
                requestBlock(user)
            })
        }

        if !model.socialState.isBlocked(user.userID) {
            result.append(.init(title: "쪽지 보내기") { model.openNoteMailbox(targetUser: user) })
        }
        result.append(.init(title: "사용자 정보") {
            model.performUserAction(.profile, user: lobbyUser(user))
        })
        return result
    }

    private func requestUnfriend(_ user: SocialUser) {
        let lobby = lobbyUser(user)
        localSocialConfirmation = SocialConfirmation(
            kind: .unfriend,
            user: lobby,
            title: "친구 해제",
            message: "\(user.nickname)님과의 친구 관계를 해제하시겠습니까?"
        )
    }

    private func requestBlock(_ user: SocialUser) {
        let lobby = lobbyUser(user)
        localSocialConfirmation = SocialConfirmation(
            kind: .block,
            user: lobby,
            title: "차단",
            message: "\(user.nickname)님을 차단하시겠습니까?\n친구 관계와 대기 중인 친구 요청이 있으면 함께 정리됩니다."
        )
    }

    @ViewBuilder
    private func actionButtons(_ actions: [FriendManagementAccessibilityAction]) -> some View {
        // 실기기 VoiceOver의 custom action 탐색 순서를 대기실과 동일하게 맞춘다.
        ForEach(actions.reversed()) { action in
            Button(action.title, action: action.perform)
        }
    }
}
