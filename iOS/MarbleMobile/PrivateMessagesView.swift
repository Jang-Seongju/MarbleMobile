import SwiftUI

struct PrivateMessagesView: View {
    @EnvironmentObject private var model: AppModel
    @State private var path: [Int] = []

    private var conversations: [PrivateConversation] {
        model.privateConversations.values.sorted {
            if model.unseenPrivateMessageUserIDs.contains($0.userID) != model.unseenPrivateMessageUserIDs.contains($1.userID) {
                return model.unseenPrivateMessageUserIDs.contains($0.userID)
            }
            return $0.nickname < $1.nickname
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if conversations.isEmpty {
                    Text("대화 없음")
                } else {
                    ForEach(conversations) { conversation in
                        NavigationLink(value: conversation.userID) {
                            Text(conversation.nickname)
                        }
                    }
                }
            }
            .navigationTitle("메시지")
            .navigationDestination(for: Int.self) { userID in
                PrivateConversationView(userID: userID)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("닫기") { model.utilitySheet = nil }
                }
            }
            .onAppear {
                if let target = model.preferredPrivateMessageUserID, path.isEmpty {
                    path.append(target)
                    model.preferredPrivateMessageUserID = nil
                }
            }
        }
    }
}

private struct PrivateConversationView: View {
    @EnvironmentObject private var model: AppModel
    let userID: Int
    @State private var draft = ""

    private var conversation: PrivateConversation? { model.privateConversations[userID] }

    var body: some View {
        List(conversation?.lines ?? []) { line in
            Text("\(line.speaker): \(line.text)")
        }
        .accessibilityLabel("대화 내용")
        .safeAreaInset(edge: .bottom) {
            HStack {
                TextField("메시지 입력", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.send)
                    .onSubmit(send)
                Button("보내기", action: send)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
        }
        .navigationTitle("\(conversation?.nickname ?? "사용자")님과의 대화")
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("뒤로") { model.utilitySheet = nil }
            }
        }
        .onAppear {
            if conversation != nil {
                model.activatePrivateConversation(userID: userID)
            }
        }
        .onDisappear {
            if model.activePrivateMessageUserID == userID { model.activePrivateMessageUserID = nil }
        }
    }

    private func send() {
        guard let conversation else { return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        model.sendPrivateMessage(userID: userID, nickname: conversation.nickname, text: text)
    }
}
