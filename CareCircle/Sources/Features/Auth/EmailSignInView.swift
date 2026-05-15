import SwiftUI

// MARK: - EmailSignInView

/// Email + password sign-in flow. Single screen that toggles between
/// "Sign in" (existing account) and "Create account" (new account).
/// Both modes funnel through `AuthState` which handles backend exchange,
/// keychain persistence, and error mapping.
struct EmailSignInView: View {
    let authState: AuthState

    @State private var mode: Mode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var displayName = ""
    @State private var isSubmitting = false
    @FocusState private var focusedField: Field?

    @Environment(\.dismiss) private var dismiss

    enum Mode: String, Hashable, CaseIterable, Identifiable {
        case signIn = "Sign in"
        case createAccount = "Create account"
        var id: String {
            rawValue
        }
    }

    enum Field: Hashable {
        case email, password, displayName
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.looseSpacing) {
                    BrandLogo(size: 56)
                        .padding(.top, Theme.spacing)

                    Picker("Mode", selection: $mode) {
                        ForEach(Mode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, Theme.spacing)
                    .padding(.top, Theme.spacing)
                    .onChange(of: mode) { _, _ in
                        // Clear any prior error when the user flips modes
                        // — the message that was valid for "sign in"
                        // doesn't necessarily apply to "create account."
                        authState.clearLastError()
                    }

                    VStack(alignment: .leading, spacing: Theme.spacing) {
                        if mode == .createAccount {
                            FormRow("Your name (optional)") {
                                TextField("Laura", text: $displayName)
                                    .textContentType(.name)
                                    .autocorrectionDisabled()
                                    .focused($focusedField, equals: .displayName)
                                    .submitLabel(.next)
                                    .onSubmit { focusedField = .email }
                            }
                        }

                        FormRow("Email") {
                            TextField("you@example.com", text: $email)
                                .textContentType(.username)
                                .keyboardType(.emailAddress)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .focused($focusedField, equals: .email)
                                .submitLabel(.next)
                                .onSubmit { focusedField = .password }
                        }

                        FormRow("Password") {
                            SecureField(
                                mode == .createAccount
                                    ? "At least 12 characters"
                                    : "Your password",
                                text: $password
                            )
                            .textContentType(mode == .createAccount ? .newPassword : .password)
                            .focused($focusedField, equals: .password)
                            .submitLabel(.go)
                            .onSubmit { submit() }
                        }

                        if mode == .createAccount {
                            Text(
                                "Use at least 12 characters. A passphrase like \u{201C}correct horse battery staple\u{201D} works well."
                            )
                            .font(.footnote)
                            .foregroundStyle(Color.ccSecondary)
                        }

                        if let error = displayedError {
                            Text(error)
                                .font(.footnote)
                                .foregroundStyle(Color.ccDanger)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityIdentifier("emailSignIn.errorMessage")
                        }
                    }
                    .padding(.horizontal, Theme.spacing)

                    Button {
                        submit()
                    } label: {
                        HStack {
                            if isSubmitting {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .tint(.white)
                            }
                            Text(mode == .signIn ? "Sign in" : "Create account")
                        }
                    }
                    .buttonStyle(.ccPrimary)
                    .disabled(!canSubmit || isSubmitting)
                    .padding(.horizontal, Theme.spacing)

                    Spacer(minLength: Theme.looseSpacing)
                }
            }
            .background(Color.ccBackground.ignoresSafeArea())
            .navigationTitle("Email sign-in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear { focusedField = .email }
        }
    }

    private var canSubmit: Bool {
        guard isValidEmail(email) else { return false }
        if mode == .createAccount {
            return password.count >= 12
        }
        return !password.isEmpty
    }

    private var displayedError: String? {
        guard let error = authState.lastError, error != .canceled else { return nil }
        return error.errorDescription
    }

    private func submit() {
        guard canSubmit, !isSubmitting else { return }
        isSubmitting = true
        let trimmedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let capturedPassword = password
        let capturedMode = mode
        Task {
            switch capturedMode {
            case .signIn:
                await authState.signInWithEmail(email: normalizedEmail, password: capturedPassword)
            case .createAccount:
                await authState.registerWithEmail(
                    email: normalizedEmail,
                    password: capturedPassword,
                    displayName: trimmedDisplayName.isEmpty ? nil : trimmedDisplayName
                )
            }
            isSubmitting = false
            // Successful sign-in dismisses by causing the root view to
            // swap; we leave the view open on error so the user can fix
            // the input.
        }
    }

    /// Cheap client-side email shape check. The server applies the
    /// authoritative Zod check — this just keeps the submit button
    /// disabled until the field looks plausibly correct.
    private func isValidEmail(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let at = trimmed.firstIndex(of: "@"), at != trimmed.startIndex else { return false }
        let domain = trimmed[trimmed.index(after: at)...]
        return domain.contains(".") && !domain.hasSuffix(".")
    }
}
