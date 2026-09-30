import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var model: AppModel
    @State private var submitting = false
    @State private var showingRegister = false
    @FocusState private var focusedField: Field?

    enum Field: Hashable { case username, password }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("아이디", text: Binding(
                        get: { model.loginUsername },
                        set: { model.updateLoginUsername($0) }
                    ))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.username)
                    .submitLabel(.next)
                    .focused($focusedField, equals: .username)
                    .onSubmit {
                        if allFieldsFilled { Task { await submitLogin() } }
                        else { focusedField = .password }
                    }

                    SecureField("비밀번호", text: $model.loginPassword)
                        .textContentType(.password)
                        .submitLabel(.go)
                        .focused($focusedField, equals: .password)
                        .onSubmit { Task { await submitLogin() } }

                    Toggle("아이디/비밀번호 저장", isOn: $model.loginSaveCredentials)
                }

                Section {
                    Button(submitting ? "로그인 중..." : "로그인") { Task { await submitLogin() } }
                        .disabled(submitting)
                    Button("회원가입") { showingRegister = true }
                }
            }
            .navigationTitle("마블 게임 - 로그인")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    MobileMainMenu(
                        context: .login,
                        loginEnabled: !submitting,
                        onLogin: { Task { await submitLogin() } }
                    )
                    .environmentObject(model)
                }
            }
            .task {
                model.loadSavedLoginIfNeeded()
            }
            .sheet(isPresented: $showingRegister) {
                RegisterView()
                    .environmentObject(model)
            }
            .alert("알림", isPresented: Binding(
                get: { model.alertMessage != nil },
                set: { if !$0 { model.alertMessage = nil } }
            )) {
                Button("확인", role: .cancel) { model.alertMessage = nil }
            } message: {
                Text(model.alertMessage ?? "")
            }
        }
    }

    private var allFieldsFilled: Bool {
        !model.loginUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !model.loginPassword.isEmpty
    }

    private func submitLogin() async {
        guard !submitting else { return }
        let trimmed = model.loginUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            model.alertMessage = "아이디를 입력해 주세요."
            focusedField = .username
            return
        }
        guard !model.loginPassword.isEmpty else {
            model.alertMessage = "비밀번호를 입력해 주세요."
            focusedField = .password
            return
        }

        submitting = true
        let ok = await model.login(
            username: trimmed,
            password: model.loginPassword,
            save: model.loginSaveCredentials
        )
        submitting = false
        if !ok {
            model.loginPassword = ""
            focusedField = .password
        }
    }
}
