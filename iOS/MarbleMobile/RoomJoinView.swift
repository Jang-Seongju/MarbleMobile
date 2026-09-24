import SwiftUI

struct RoomJoinView: View {
    @EnvironmentObject private var model: AppModel
    @AccessibilityFocusState private var passwordFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                if let room = model.pendingRoomJoin {
                    Section("방 정보") {
                        Text("\(room.id): \(room.title)")
                        Text(verbatim: "\(room.current.map(String.init) ?? "알 수 없음")/\(room.maxPlayers.map(String.init) ?? "알 수 없음")명")
                        Text("비공개 방")
                    }
                }

                Section("비밀번호") {
                    SecureField("비밀번호", text: $model.roomJoinPassword)
                        .textContentType(.password)
                        .submitLabel(.join)
                        .onSubmit { model.submitPendingPrivateRoomJoin() }
                        .disabled(model.isRoomJoinPending)
                        .accessibilityFocused($passwordFocused)

                    if let error = model.roomJoinErrorMessage {
                        Text(error)
                            .foregroundStyle(.red)
                            .accessibilityLabel("오류")
                            .accessibilityValue(error)
                    }
                }
            }
            .navigationTitle("비공개 방 참여")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { model.cancelPendingRoomJoin() }
                        .disabled(model.isRoomJoinPending)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(model.isRoomJoinPending ? "참여 중" : "참여하기") {
                        model.submitPendingPrivateRoomJoin()
                    }
                    .disabled(model.isRoomJoinPending || model.roomJoinPassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                DispatchQueue.main.async { passwordFocused = true }
            }
        }
        .interactiveDismissDisabled(model.isRoomJoinPending)
    }
}
