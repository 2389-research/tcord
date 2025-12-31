// ABOUTME: Authentication view for signing in with Apple.
// ABOUTME: Shown when user is not authenticated.

import SwiftUI
import AuthenticationServices

struct AuthView: View {

    @EnvironmentObject var authService: AuthService
    @State private var showError = false

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // App icon/branding
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.blue)

            Text("Voice Notes")
                .font(.largeTitle)
                .bold()

            Text("Record voice memos on your Apple Watch and access them anywhere.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)

            Spacer()

            // Sign in buttons
            VStack(spacing: 16) {
                SignInWithAppleButton { request in
                    request.requestedScopes = [.email, .fullName]
                } onCompletion: { result in
                    switch result {
                    case .success:
                        Task {
                            do {
                                try await authService.signInWithApple()
                            } catch {
                                showError = true
                            }
                        }
                    case .failure:
                        showError = true
                    }
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 50)
                .padding(.horizontal)

                // Anonymous sign in for testing
                #if DEBUG
                Button("Continue as Guest") {
                    Task {
                        try? await authService.signInAnonymously()
                    }
                }
                .foregroundColor(.secondary)
                #endif
            }

            Spacer()
        }
        .alert("Sign In Failed", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text("Please try again.")
        }
    }
}
