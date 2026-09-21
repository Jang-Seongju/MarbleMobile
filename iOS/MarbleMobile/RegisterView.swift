import SwiftUI

struct RegisterView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var username = ""
    @State private var nickname = ""
    @State private var password = ""
    @State private var passwordConfirm = ""
    @State private var usernameChecked = false
    @State private var nicknameChecked = false
    @State private var submitting = false
    @State private var alertMessage: String?
    @State private var registrationCompleted = false
    @AccessibilityFocusState private var focus: Field?

    enum Field: Hashable { case username, nickname, password, confirm }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("아이디 (4~20자, 영문/숫자/언더스코어)", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityLabel("아이디 입력")
                        .accessibilityFocused($focus, equals: .username)
                        .onChange(of: username) { _, _ in usernameChecked = false }
                        .onSubmit { Task { await advanceUsername() } }

                    TextField("닉네임 (한글 1~10자 또는 영문/혼합 2~20자)", text: $nickname)
                        .accessibilityLabel("닉네임 입력")
                        .accessibilityFocused($focus, equals: .nickname)
                        .onChange(of: nickname) { _, _ in nicknameChecked = false }
                        .onSubmit { Task { await advanceNickname() } }

                    SecureField("비밀번호 (4자 이상)", text: $password)
                        .accessibilityLabel("비밀번호 입력")
                        .accessibilityFocused($focus, equals: .password)
                        .onSubmit {
                            if allFilled { Task { await register() } }
                            else { focus = .confirm }
                        }

                    SecureField("비밀번호 확인", text: $passwordConfirm)
                        .accessibilityLabel("비밀번호 확인 입력")
                        .accessibilityFocused($focus, equals: .confirm)
                        .onSubmit { Task { await register() } }
                }

                Section {
                    Button(submitting ? "처리 중..." : "회원가입") { Task { await register() } }
                        .disabled(submitting)
                    Button("취소", role: .cancel) { dismiss() }
                }
            }
            .navigationTitle("마블 게임 - 회원가입")
            .task { focus = .username }
            .alert(registrationCompleted ? "안내" : "알림", isPresented: Binding(
                get: { alertMessage != nil },
                set: { if !$0 { alertMessage = nil } }
            )) {
                Button("확인", role: .cancel) {
                    alertMessage = nil
                    if registrationCompleted { dismiss() }
                }
            } message: {
                Text(alertMessage ?? "")
            }
        }
    }

    private var allFilled: Bool {
        !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !password.isEmpty && !passwordConfirm.isEmpty
    }

    private func advanceUsername() async {
        if allFilled { await register(); return }
        let value = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { showError("아이디를 입력해 주세요.", focus: .username); return }
        do {
            if try await model.api.checkUsername(value) {
                usernameChecked = false
                showError("이미 사용 중인 아이디입니다.", focus: .username)
                return
            }
            usernameChecked = true
            focus = .nickname
        } catch {
            showError(error.localizedDescription, focus: .username)
        }
    }

    private func advanceNickname() async {
        if allFilled { await register(); return }
        let value = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { showError("닉네임을 입력해 주세요.", focus: .nickname); return }
        do {
            if try await model.api.checkNickname(value) {
                nicknameChecked = false
                showError("이미 사용 중인 닉네임입니다.", focus: .nickname)
                return
            }
            nicknameChecked = true
            focus = .password
        } catch {
            showError(error.localizedDescription, focus: .nickname)
        }
    }

    private func register() async {
        guard !submitting else { return }
        let u = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let n = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !u.isEmpty else { showError("아이디를 입력해 주세요.", focus: .username); return }
        guard !n.isEmpty else { showError("닉네임을 입력해 주세요.", focus: .nickname); return }
        guard !password.isEmpty else { showError("비밀번호를 입력해 주세요.", focus: .password); return }
        guard !passwordConfirm.isEmpty else { showError("비밀번호 확인을 입력해 주세요.", focus: .confirm); return }
        guard password == passwordConfirm else {
            password = ""
            passwordConfirm = ""
            showError("비밀번호가 일치하지 않습니다.", focus: .password)
            return
        }

        submitting = true
        defer { submitting = false }
        do {
            if !usernameChecked {
                if try await model.api.checkUsername(u) {
                    usernameChecked = false
                    showError("이미 사용 중인 아이디입니다.", focus: .username)
                    return
                }
                usernameChecked = true
            }
            if !nicknameChecked {
                if try await model.api.checkNickname(n) {
                    nicknameChecked = false
                    showError("이미 사용 중인 닉네임입니다.", focus: .nickname)
                    return
                }
                nicknameChecked = true
            }
            try await model.api.register(username: u, nickname: n, password: password)
            registrationCompleted = true
            alertMessage = "회원가입이 완료됐습니다. 로그인 화면으로 돌아갑니다."
        } catch {
            handleRegistrationError(error.localizedDescription)
        }
    }

    private func handleRegistrationError(_ message: String) {
        if message.contains("아이디") {
            usernameChecked = false
            showError(message, focus: .username)
        } else if message.contains("닉네임") {
            nicknameChecked = false
            showError(message, focus: .nickname)
        } else if message.contains("비밀번호") {
            password = ""
            passwordConfirm = ""
            showError(message, focus: .password)
        } else {
            showError(message, focus: nil)
        }
    }

    private func showError(_ message: String, focus field: Field?) {
        registrationCompleted = false
        alertMessage = message
        if let field { focus = field }
    }
}
