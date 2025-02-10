import SwiftUI
import FirebaseAuth
import FacebookLogin
import AuthenticationServices
import CryptoKit

struct LoginView: View {
    @ObservedObject var presenter: LoginPresenter

    @State private var email: String = ""
    @State private var password: String = ""
    @State private var rememberMe: Bool = false
    @State private var errorMessage: String?
    @State private var isLoading: Bool = false
    @State private var currentNonce: String?

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Hi, Welcome! 👋")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Email address or phone number")
                    TextField("Your email", text: $email)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)

                    Text("Password")
                    SecureField("Password", text: $password)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }

                HStack {
                    Toggle("Remember me", isOn: $rememberMe)
                        .toggleStyle(SwitchToggleStyle(tint: .black))
                    Spacer()
                    NavigationLink(destination: ForgotPasswordView()) {
                        Text("Forgot password?")
                    }
                    .foregroundColor(.blue)
                }

                if let error = errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.footnote)
                }

                Button(action: loginWithFirebase) {
                    if isLoading {
                        ProgressView()
                    } else {
                        Text("Log in")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.black)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                }

                Text("Or with")
                    .font(.footnote)
                    .foregroundColor(.gray)

                // Google Login
                Button(action: {
                    presenter.handleGoogleLogin()
                }) {
                    HStack {
                        Image("googleLogo")
                            .resizable()
                            .frame(width: 20, height: 20)
                        Text("Continue with Google")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                }

                // GitHub Login
                Button(action: {
                    presenter.handleGitHubLogin()
                }) {
                    HStack {
                        Image("githubLogo")
                            .resizable()
                            .frame(width: 20, height: 20)
                        Text("Continue with GitHub")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                }
                
                // Facebook Login
                Button(action: {
                    handleFacebookLogin()
                }) {
                    HStack {
                        Image("facebookLogo")
                            .resizable()
                            .frame(width: 20, height: 20)
                            .foregroundColor(.blue)
                        Text("Continue with Facebook")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                }

                // Sign in with Apple Button
                SignInWithAppleButton(
                    .signIn,
                    onRequest: configureAppleRequest,
                    onCompletion: handleAppleSignIn
                )
                .signInWithAppleButtonStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 45)
                .cornerRadius(8)

                Spacer()

                HStack {
                    Text("Don’t have an account?")
                    NavigationLink(destination: SignUpView()) {
                        Text("Sign up")
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.blue)
                }
            }
            .padding()
        }
    }

    private func loginWithFirebase() {
        guard !email.isEmpty, !password.isEmpty else {
            errorMessage = "Please enter both email and password."
            return
        }

        isLoading = true
        errorMessage = nil

        Auth.auth().signIn(withEmail: email, password: password) { result, error in
            isLoading = false

            if let error = error {
                self.errorMessage = error.localizedDescription
            } else {
                print("User signed in: \(result?.user.uid ?? "No UID")")
                presenter.handleSuccessfulLogin()
            }
        }
    }

    private func handleFacebookLogin() {
        let loginManager = LoginManager()
        loginManager.logIn(permissions: ["public_profile", "email"], from: nil) { result, error in
            if let error = error {
                self.errorMessage = "Facebook login failed: \(error.localizedDescription)"
                return
            }

            guard let result = result, !result.isCancelled else {
                self.errorMessage = "Facebook login was cancelled."
                return
            }

            guard let accessToken = AccessToken.current else {
                self.errorMessage = "Failed to get access token."
                return
            }

            let credential = FacebookAuthProvider.credential(withAccessToken: accessToken.tokenString)
            Auth.auth().signIn(with: credential) { authResult, error in
                if let error = error {
                    self.errorMessage = "Firebase login failed: \(error.localizedDescription)"
                } else {
                    print("Successfully logged in with Facebook: \(authResult?.user.uid ?? "No UID")")
                    presenter.handleSuccessfulLogin()
                }
            }
        }
    }

    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length

        while remainingLength > 0 {
            let randoms: [UInt8] = (0..<16).map { _ in
                var random: UInt8 = 0
                let errorCode = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
                if errorCode != errSecSuccess {
                    fatalError("Unable to generate nonce.")
                }
                return random
            }

            randoms.forEach { random in
                if remainingLength == 0 {
                    return
                }

                if random < charset.count {
                    result.append(charset[Int(random)])
                    remainingLength -= 1
                }
            }
        }

        return result
    }

    
    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        return hashedData.compactMap { String(format: "%02x", $0) }.joined()
    }

    private func configureAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = randomNonceString()
        currentNonce = nonce
        request.nonce = sha256(nonce)
        request.requestedScopes = [.fullName, .email]
    }

    private func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            if let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential {
                guard let identityToken = appleIDCredential.identityToken,
                      let tokenString = String(data: identityToken, encoding: .utf8),
                      let nonce = currentNonce else {
                    self.errorMessage = "Invalid Apple Sign-In request."
                    return
                }

                let credential = OAuthProvider.credential(
                    withProviderID: "apple.com",
                    idToken: tokenString,
                    rawNonce: nonce
                )

                Auth.auth().signIn(with: credential) { authResult, error in
                    if let error = error {
                        self.errorMessage = "Apple Sign-In failed: \(error.localizedDescription)"
                    } else {
                        print("Successfully signed in with Apple.")
                        presenter.handleSuccessfulLogin()
                    }
                }
            }
        case .failure(let error):
            self.errorMessage = "Apple Sign-In failed: \(error.localizedDescription)"
        }
    }
}
