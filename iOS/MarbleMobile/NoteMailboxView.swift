import SwiftUI
import MarbleMobileCore

struct NoteMailboxView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var path: [Int] = []

    private var counterpartIDs: [Int] {
        Array(Set(model.notes.map { $0.counterpart.userID })).sorted { lhs, rhs in
            let l = latestNote(for: lhs)?.createdAt ?? ""
            let r = latestNote(for: rhs)?.createdAt ?? ""
            return l > r
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if counterpartIDs.isEmpty {
                    Text("쪽지 없음")
                } else {
                    ForEach(counterpartIDs, id: \.self) { userID in
                        NavigationLink(value: userID) {
                            Text(counterpartLabel(userID))
                        }
                    }
                }
            }
            .navigationTitle("쪽지함")
            .navigationDestination(for: Int.self) { userID in
                NoteConversationView(userID: userID)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("닫기") { dismiss() }
                }
            }
            .onAppear {
                model.requestNoteMailbox()
                if let target = model.preferredNoteUserID, path.isEmpty {
                    path.append(target)
                    model.preferredNoteUserID = nil
                }
            }
        }
    }

    private func latestNote(for userID: Int) -> NoteSnapshot? {
        model.notes.filter { $0.counterpart.userID == userID }.first
    }

    private func counterpartLabel(_ userID: Int) -> String {
        let notes = model.notes.filter { $0.counterpart.userID == userID }
        let nickname = notes.first?.counterpart.nickname
            ?? model.users.first(where: { $0.id == userID })?.nickname
            ?? "사용자 \(userID)"
        let unread = notes.filter { $0.direction == .received && !$0.isRead }.count
        return unread > 0 ? "\(nickname), 읽지 않음 \(unread)개" : nickname
    }
}

private struct NoteConversationView: View {
    @EnvironmentObject private var model: AppModel
    let userID: Int
    @State private var draft = ""
    @AccessibilityFocusState private var focusedNoteID: Int?

    private var notes: [NoteSnapshot] {
        Array(model.notes.filter { $0.counterpart.userID == userID }.reversed())
    }

    private var nickname: String {
        notes.first?.counterpart.nickname
            ?? model.users.first(where: { $0.id == userID })?.nickname
            ?? "사용자 \(userID)"
    }

    var body: some View {
        VStack {
            List(notes) { note in
                Text(rowText(note))
                    .accessibilityFocused($focusedNoteID, equals: note.noteID)
                    .onTapGesture { model.markNoteRead(note.noteID) }
            }
            .accessibilityLabel("쪽지 내역")
            .onChange(of: focusedNoteID) { _, noteID in
                if let noteID { model.markNoteRead(noteID) }
            }

            TextField("작성 내용", text: $draft, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .onSubmit(send)
                .padding(.horizontal)
            Button("보내기", action: send)
                .padding(.bottom)
        }
        .navigationTitle(nickname)
    }

    private func rowText(_ note: NoteSnapshot) -> String {
        let sender = note.direction == .sent ? "당신" : note.counterpart.nickname
        let unread = note.direction == .received && !note.isRead ? "읽지 않음, " : ""
        return "\(unread)\(sender): \(note.body)"
    }

    private func send() {
        let text = draft
        draft = ""
        model.sendNote(targetUserID: userID, body: text)
    }
}
