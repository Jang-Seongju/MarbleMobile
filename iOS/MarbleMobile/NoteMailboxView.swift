import SwiftUI
import MarbleMobileCore

private enum NoteMailboxRoute: Hashable {
    case conversation(Int)
    case compose
}

private struct NoteConversationDeleteTarget: Identifiable {
    let userID: Int
    let nickname: String
    var id: Int { userID }
}

struct NoteMailboxView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var path: [NoteMailboxRoute] = []
    @State private var deleteTarget: NoteConversationDeleteTarget?
    @AccessibilityFocusState private var focusedCounterpartID: Int?
    @AccessibilityFocusState private var newNoteFocused: Bool

    private var counterpartIDs: [Int] {
        Array(Set(model.notes.map { $0.counterpart.userID })).sorted { lhs, rhs in
            let l = latestNote(for: lhs)?.createdAt ?? ""
            let r = latestNote(for: rhs)?.createdAt ?? ""
            if l != r { return l > r }
            return lhs < rhs
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    NavigationLink("새 쪽지", value: NoteMailboxRoute.compose)
                        .accessibilityFocused($newNoteFocused)
                }

                Section("대화 상대") {
                    if counterpartIDs.isEmpty {
                        Text("쪽지 없음")
                    } else {
                        ForEach(counterpartIDs, id: \.self) { userID in
                            NavigationLink(value: NoteMailboxRoute.conversation(userID)) {
                                Text(counterpartLabel(userID))
                            }
                            .accessibilityFocused($focusedCounterpartID, equals: userID)
                            .accessibilityActions {
                                Button("이 사람과의 쪽지 모두 삭제") {
                                    deleteTarget = .init(userID: userID, nickname: counterpartNickname(userID))
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("쪽지함")
            .navigationDestination(for: NoteMailboxRoute.self) { route in
                switch route {
                case .conversation(let userID):
                    NoteConversationView(userID: userID)
                case .compose:
                    NewNoteComposeView()
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("닫기") { dismiss() }
                }
            }
            .onAppear {
                model.requestNoteMailbox()
                DispatchQueue.main.async { applyInitialFocusOrTarget() }
            }
            .onChange(of: counterpartIDs) { _, ids in
                guard path.isEmpty else { return }
                if let focusedCounterpartID, ids.contains(focusedCounterpartID) { return }
                DispatchQueue.main.async {
                    if let first = ids.first {
                        focusedCounterpartID = first
                    } else {
                        newNoteFocused = true
                    }
                }
            }
            .alert(item: $deleteTarget) { target in
                Alert(
                    title: Text("쪽지 삭제"),
                    message: Text("\(target.nickname)님과의 모든 쪽지를 삭제하시겠습니까?"),
                    primaryButton: .destructive(Text("삭제")) {
                        model.deleteNoteConversation(userID: target.userID)
                    },
                    secondaryButton: .cancel(Text("취소"))
                )
            }
        }
    }

    private func applyInitialFocusOrTarget() {
        if let target = model.preferredNoteUserID {
            path = [.conversation(target)]
            model.preferredNoteUserID = nil
            return
        }
        if let first = counterpartIDs.first {
            focusedCounterpartID = first
        } else {
            newNoteFocused = true
        }
    }

    private func latestNote(for userID: Int) -> NoteSnapshot? {
        model.notes.first { $0.counterpart.userID == userID }
    }

    private func counterpartNickname(_ userID: Int) -> String {
        if let note = model.notes.first(where: { $0.counterpart.userID == userID }) {
            return note.counterpart.nickname
        }
        if let user = model.users.first(where: { $0.id == userID }) {
            return user.nickname
        }
        if let user = model.socialState.friends.first(where: { $0.userID == userID }) {
            return user.nickname
        }
        if let request = model.socialState.incomingRequest(for: userID) {
            return request.user.nickname
        }
        if let request = model.socialState.outgoingRequest(for: userID) {
            return request.user.nickname
        }
        if let user = model.socialState.blockedUsers.first(where: { $0.userID == userID }) {
            return user.nickname
        }
        return "사용자 \(userID)"
    }

    private func counterpartLabel(_ userID: Int) -> String {
        let userNotes = model.notes.filter { $0.counterpart.userID == userID }
        let nickname = counterpartNickname(userID)
        let unread = userNotes.filter { $0.direction == .received && !$0.isRead }.count
        return unread > 0 ? "\(nickname), 읽지 않음 \(unread)개" : nickname
    }
}

private struct NoteConversationView: View {
    @EnvironmentObject private var model: AppModel
    let userID: Int
    @State private var draft = ""
    @AccessibilityFocusState private var focusedNoteID: Int?

    private var conversationNotes: [NoteSnapshot] {
        Array(model.notes.filter { $0.counterpart.userID == userID }.reversed())
    }

    private var nickname: String {
        if let nickname = conversationNotes.first?.counterpart.nickname {
            return nickname
        }
        if let nickname = model.socialState.friends.first(where: { $0.userID == userID })?.nickname {
            return nickname
        }
        if let nickname = model.socialState.incomingRequest(for: userID)?.user.nickname {
            return nickname
        }
        if let nickname = model.socialState.outgoingRequest(for: userID)?.user.nickname {
            return nickname
        }
        if let nickname = model.users.first(where: { $0.id == userID })?.nickname {
            return nickname
        }
        return "사용자 \(userID)"
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack {
            List(conversationNotes) { note in
                Text(NotePresentationFormatter.noteRowText(
                    note,
                    selfNickname: model.session?.identity.nickname ?? "당신"
                ))
                .accessibilityFocused($focusedNoteID, equals: note.noteID)
                .accessibilityActions {
                    Button("쪽지 삭제") { model.deleteNote(note.noteID) }
                }
            }
            .accessibilityLabel("쪽지 내역")
            .onAppear {
                DispatchQueue.main.async { focusedNoteID = conversationNotes.last?.noteID }
            }
            .onChange(of: focusedNoteID) { _, noteID in
                if let noteID { model.markNoteRead(noteID) }
            }
            .onChange(of: conversationNotes) { _, updated in
                if let focusedNoteID, updated.contains(where: { $0.noteID == focusedNoteID }) { return }
                DispatchQueue.main.async { self.focusedNoteID = updated.last?.noteID }
            }

            TextField("작성 내용", text: $draft, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .onSubmit(send)
                .padding(.horizontal)

            Button("보내기", action: send)
                .disabled(!canSend)
                .padding(.bottom)
        }
        .navigationTitle(nickname)
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        model.sendNote(targetUserID: userID, body: text)
        draft = ""
    }
}

private struct NewNoteComposeView: View {
    @EnvironmentObject private var model: AppModel
    @State private var searchText = ""
    @State private var selectedRecipient: SocialUser?
    @State private var draft = ""
    @AccessibilityFocusState private var focusedSearchResultID: Int?
    @AccessibilityFocusState private var searchFieldFocused: Bool

    private var canSearch: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canSend: Bool {
        selectedRecipient != nil && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        List {
            Section("받는이 검색") {
                TextField("닉네임", text: $searchText)
                    .submitLabel(.search)
                    .onSubmit(search)
                    .accessibilityFocused($searchFieldFocused)
                Button("검색", action: search)
                    .disabled(!canSearch)
            }

            Section("검색 결과") {
                if model.noteRecipientSearchResults.isEmpty {
                    Text("항목 없음")
                } else {
                    ForEach(model.noteRecipientSearchResults, id: \.userID) { user in
                        Button(user.nickname) {
                            selectedRecipient = user
                        }
                        .accessibilityFocused($focusedSearchResultID, equals: user.userID)
                    }
                }
            }

            Section("받는이") {
                Text(selectedRecipient?.nickname ?? "선택되지 않음")
            }

            Section("작성 내용") {
                TextField("작성 내용", text: $draft, axis: .vertical)
                Button("보내기", action: send)
                    .disabled(!canSend)
            }
        }
        .navigationTitle("새 쪽지")
        .onAppear { model.clearNoteRecipientSearchResults() }
        .onChange(of: model.noteRecipientSearchResults) { _, results in
            DispatchQueue.main.async {
                if let first = results.first {
                    focusedSearchResultID = first.userID
                } else if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    model.announce("검색 결과가 없습니다.")
                    searchFieldFocused = true
                }
            }
        }
    }

    private func search() {
        guard canSearch else { return }
        selectedRecipient = nil
        model.searchNoteRecipients(searchText)
    }

    private func send() {
        guard let recipient = selectedRecipient else { return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        model.sendNote(targetUserID: recipient.userID, body: text)
        draft = ""
    }
}
