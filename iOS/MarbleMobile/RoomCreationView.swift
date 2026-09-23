import SwiftUI
import MarbleMobileCore

struct RoomCreationView: View {
    enum Visibility: String, CaseIterable, Identifiable {
        case publicRoom = "공개"
        case privateRoom = "비공개"
        var id: String { rawValue }
    }

    enum Field: Hashable {
        case title
        case password
    }

    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var maxPlayers = 4
    @State private var visibility: Visibility = .publicRoom
    @State private var password = ""
    @FocusState private var focusedField: Field?

    var body: some View {
        NavigationStack {
            Form {
                Section("방 제목") {
                    TextField("방 제목", text: $title)
                        .focused($focusedField, equals: .title)
                        .submitLabel(.done)
                        .onSubmit { submit() }
                }

                Section("참여 인원") {
                    Picker("참여 인원", selection: $maxPlayers) {
                        Text("2명").tag(2)
                        Text("3명").tag(3)
                        Text("4명").tag(4)
                    }
                    .pickerStyle(.segmented)
                }

                Section("공개 설정") {
                    Picker("공개 설정", selection: $visibility) {
                        ForEach(Visibility.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: visibility) { _, newValue in
                        if newValue == .publicRoom { password = "" }
                    }
                }

                if visibility == .privateRoom {
                    Section("비밀번호") {
                        SecureField("비밀번호", text: $password)
                            .focused($focusedField, equals: .password)
                            .submitLabel(.done)
                            .onSubmit { submit() }
                    }
                }

                Section {
                    Button("개설") { submit() }
                        .disabled(model.isRoomCreationPending)
                    Button("취소", role: .cancel) { dismiss() }
                        .disabled(model.isRoomCreationPending)
                }
            }
            .navigationTitle("방 개설")
            .interactiveDismissDisabled(model.isRoomCreationPending)
            .alert("알림", isPresented: Binding(
                get: { model.roomCreationErrorMessage != nil },
                set: { if !$0 { model.roomCreationErrorMessage = nil } }
            )) {
                Button("확인", role: .cancel) {
                    let message = model.roomCreationErrorMessage
                    model.roomCreationErrorMessage = nil
                    restoreFocus(after: message)
                }
            } message: {
                Text(model.roomCreationErrorMessage ?? "")
            }
        }
    }

    private func submit() {
        guard !model.isRoomCreationPending else { return }
        do {
            let request = try RoomCreationRequest(
                title: title,
                maxPlayers: maxPlayers,
                isPrivate: visibility == .privateRoom,
                password: password
            )
            model.createRoom(request)
        } catch let error as RoomCreationValidationError {
            model.roomCreationErrorMessage = error.localizedDescription
        } catch {
            model.roomCreationErrorMessage = "방 개설 정보를 확인해 주세요."
        }
    }

    private func restoreFocus(after message: String?) {
        switch message {
        case RoomCreationValidationError.missingTitle.localizedDescription:
            focusedField = .title
        case RoomCreationValidationError.missingPrivatePassword.localizedDescription:
            focusedField = .password
        default:
            break
        }
    }
}
