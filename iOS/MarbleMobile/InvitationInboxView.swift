import SwiftUI
import MarbleMobileCore

struct InvitationInboxView: View {
    @EnvironmentObject private var model: AppModel
    @State private var roomInfoText: String?

    var body: some View {
        NavigationStack {
            Group {
                if model.invitations.isEmpty {
                    ContentUnavailableView(
                        "초대 없음",
                        systemImage: "envelope.open",
                        description: Text("현재 받은 초대가 없습니다.")
                    )
                } else {
                    List {
                        ForEach(model.invitations) { invitation in
                            invitationRow(invitation)
                        }
                    }
                }
            }
            .navigationTitle("초대")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { model.dismissInvitationInbox() }
                }
            }
        }
        .onDisappear {
            model.dismissInvitationInbox()
        }
        .sheet(isPresented: Binding(
            get: { roomInfoText != nil },
            set: { presented in
                if !presented { roomInfoText = nil }
            }
        )) {
            NavigationStack {
                ScrollView {
                    Text(roomInfoText ?? "")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .textSelection(.enabled)
                }
                .navigationTitle("방 정보")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("닫기") { roomInfoText = nil }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func invitationRow(_ invitation: GameInvitation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                model.acceptInvitation(invitation)
            } label: {
                Text(invitation.listLabel)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .disabled(model.pendingInvitationID != nil)
            .accessibilityHint("두 번 탭하여 수락합니다.")

            HStack(spacing: 8) {
                Button("메시지 보내기, 사용할 수 없음") { }
                    .disabled(true)

                Button("방 정보") {
                    roomInfoText = model.invitationRoomInfoText(invitation)
                }
                .disabled(model.pendingInvitationID != nil)
            }
            .buttonStyle(.bordered)

            if model.pendingInvitationID == invitation.inviteID {
                ProgressView("입장 요청 중")
                    .accessibilityLabel("입장 요청 중")
            }
        }
        .padding(.vertical, 4)
    }
}
