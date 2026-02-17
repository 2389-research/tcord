// ABOUTME: Authentication view for signing in with Apple.
// ABOUTME: Shown when user is not authenticated.

import SwiftUI
import AuthenticationServices

struct AuthView: View {

    @EnvironmentObject var authService: AuthService
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // App icon/branding
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.blue)

            Text("tcord")
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
                                errorMessage = describeAuthError(error)
                                showError = true
                            }
                        }
                    case .failure(let error):
                        errorMessage = describeAuthError(error)
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
                        do {
                            try await authService.signInAnonymously()
                        } catch {
                            errorMessage = describeAuthError(error)
                            showError = true
                        }
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
            Text(errorMessage)
        }
    }

    private func describeAuthError(_ error: Error) -> String {
        let nsError = error as NSError

        // Handle ASAuthorizationError (Sign in with Apple cancellation/failures)
        if nsError.domain == ASAuthorizationError.errorDomain {
            switch ASAuthorizationError.Code(rawValue: nsError.code) {
            case .canceled:
                return "Sign in was cancelled."
            case .failed:
                return "Sign in failed. Please try again."
            case .invalidResponse:
                return "Invalid response from Apple. Please try again."
            case .notHandled:
                return "Sign in request was not handled."
            case .unknown:
                return "An unknown error occurred. Please try again."
            default:
                return "Sign in failed. Please try again."
            }
        }

        // Handle Firebase Auth errors
        if nsError.domain == "FIRAuthErrorDomain" {
            switch nsError.code {
            case 17020: // Network error
                return "Network error. Please check your connection."
            case 17999: // Internal error
                return "Authentication service error. Please try again later."
            default:
                return error.localizedDescription
            }
        }

        return error.localizedDescription
    }
}
