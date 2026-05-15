import AuthenticationServices
import CryptoKit
import SwiftUI

// MARK: - SignInView

struct SignInView: View {
    let authState: AuthState

    @State private var currentHashedNonce = ""
    @State private var isPresentingEmailSheet = false
    @State private var isStartingGoogleSignIn = false

    var body: some View {
        VStack(spacing: Theme.looseSpacing) {
            Spacer(minLength: 0)

            VStack(spacing: Theme.spacing) {
                Image(systemName: "heart.text.square.fill")
                    .font(.system(size: 72, weight: .light))
                    .foregroundStyle(Color.ccPrimary)
                    .accessibilityHidden(true)

                Text("CareCircle")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(Color.ccText)

                Text("Coordinate care for the people who count on you.")
                    .font(.title3)
                    .foregroundStyle(Color.ccSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.looseSpacing)
            }

            Spacer(minLength: 0)

            VStack(spacing: Theme.spacing) {
                SignInWithAppleButton(.signIn) { request in
                    let raw = Self.randomNonce()
                    let hashed = Self.sha256(raw)
                    currentHashedNonce = hashed
                    request.requestedScopes = [.fullName, .email]
                    request.nonce = hashed
                } onCompletion: { result in
                    let hashed = currentHashedNonce
                    Task {
                        await authState.completeAppleSignIn(result: result, hashedNonce: hashed)
                    }
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 52)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))

                if authState.canSignInWithGoogle {
                    Button {
                        authState.clearLastError()
                        isStartingGoogleSignIn = true
                        Task {
                            await authState.signInWithGoogle()
                            isStartingGoogleSignIn = false
                        }
                    } label: {
                        HStack {
                            if isStartingGoogleSignIn {
                                ProgressView()
                                    .progressViewStyle(.circular)
                            }
                            Label("Continue with Google", systemImage: "g.circle.fill")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.ccSecondary)
                    .disabled(isStartingGoogleSignIn)
                    .accessibilityIdentifier("signIn.googleButton")
                }

                Button {
                    authState.clearLastError()
                    isPresentingEmailSheet = true
                } label: {
                    Label("Continue with email", systemImage: "envelope.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.ccSecondary)
                .accessibilityIdentifier("signIn.emailButton")

                if let error = authState.lastError, error != .canceled {
                    Text(error.errorDescription ?? "Sign in failed.")
                        .font(.footnote)
                        .foregroundStyle(Color.ccDanger)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, Theme.looseSpacing)
            .padding(.bottom, Theme.looseSpacing)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.ccBackground.ignoresSafeArea())
        .sheet(isPresented: $isPresentingEmailSheet) {
            EmailSignInView(authState: authState)
        }
    }

    // MARK: Nonce helpers

    private static func randomNonce(length: Int = 32) -> String {
        precondition(length > 0, "Nonce length must be positive")
        let charset: [Character] =
            Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length

        while remaining > 0 {
            var randoms = [UInt8](repeating: 0, count: 16)
            let status = SecRandomCopyBytes(kSecRandomDefault, randoms.count, &randoms)
            guard status == errSecSuccess else {
                fatalError("SecRandomCopyBytes failed with status \(status)")
            }

            for byte in randoms where remaining > 0 {
                if byte < charset.count {
                    result.append(charset[Int(byte)])
                    remaining -= 1
                }
            }
        }
        return result
    }

    private static func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashed = SHA256.hash(data: inputData)
        return hashed.map { String(format: "%02x", $0) }.joined()
    }
}
