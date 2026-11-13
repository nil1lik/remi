import AuthenticationServices
import CryptoKit
import Foundation
import UIKit

/// Apple ve Google ile giriş. Sağlayıcıdan alınan kimlik belgesi (id_token) Remi sunucusuna gönderilir;
/// sunucu imzayı, uygulamaya ait olduğunu ve nonce'u doğrular. Şifre hiçbir yerde tutulmaz.
@MainActor
final class SignInService: NSObject {
    struct Credential {
        var provider: String
        var idToken: String
        var nonce: String?
        var givenName: String?
    }

    enum SignInError: Error { case cancelled, failed, notConfigured }

    // MARK: Apple

    private var appleContinuation: CheckedContinuation<ASAuthorization, Error>?

    func signInWithApple() async throws -> Credential {
        // Her girişte yeni, rastgele nonce: Apple'a özeti gider, sunucu belgede aynı özeti arar.
        let nonce = Self.randomString()
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName]
        request.nonce = Self.sha256(nonce)

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        let authorization: ASAuthorization = try await withCheckedThrowingContinuation { continuation in
            appleContinuation = continuation
            controller.performRequests()
        }

        guard let apple = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = apple.identityToken, let token = String(data: tokenData, encoding: .utf8)
        else { throw SignInError.failed }
        return Credential(provider: "apple", idToken: token, nonce: nonce, givenName: apple.fullName?.givenName)
    }

    // MARK: Google (SDK'sız, PKCE ile)

    /// Info.plist'teki GoogleClientID (iOS istemci kimliği). Boşsa Google girişi kapalıdır.
    static var googleClientID: String? {
        let id = (Bundle.main.object(forInfoDictionaryKey: "GoogleClientID") as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
        return id.hasSuffix(".apps.googleusercontent.com") ? id : nil
    }

    private var webSession: ASWebAuthenticationSession?

    func signInWithGoogle() async throws -> Credential {
        guard let clientID = Self.googleClientID else { throw SignInError.notConfigured }
        // Yönlendirme şeması: istemci kimliğinin tersi (Google iOS istemcileri için standart).
        let scheme = clientID.split(separator: ".").reversed().joined(separator: ".")
        let redirect = "\(scheme):/oauth2redirect"
        let verifier = Self.randomString(length: 64)
        let challenge = Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        let state = Self.randomString()
        let nonce = Self.randomString()

        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: redirect),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: "openid profile"),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state", value: state),
            .init(name: "nonce", value: nonce),
            .init(name: "prompt", value: "select_account"),
        ]

        let callback: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: components.url!, callbackURLScheme: scheme) { url, error in
                if let url { continuation.resume(returning: url) }
                else if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin { continuation.resume(throwing: SignInError.cancelled) }
                else { continuation.resume(throwing: SignInError.failed) }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = true
            webSession = session
            session.start()
        }

        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        // state uyuşmazsa yanıt bizim isteğimize ait değildir.
        guard items.first(where: { $0.name == "state" })?.value == state,
              let code = items.first(where: { $0.name == "code" })?.value
        else { throw SignInError.failed }

        var tokenRequest = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        tokenRequest.httpMethod = "POST"
        tokenRequest.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "code", value: code),
            .init(name: "code_verifier", value: verifier),
            .init(name: "grant_type", value: "authorization_code"),
            .init(name: "redirect_uri", value: redirect),
        ]
        tokenRequest.httpBody = form.percentEncodedQuery?.data(using: .utf8)

        struct GoogleTokens: Decodable { var id_token: String }
        let (data, response) = try await URLSession(configuration: .ephemeral).data(for: tokenRequest)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let tokens = try? JSONDecoder().decode(GoogleTokens.self, from: data)
        else { throw SignInError.failed }
        return Credential(provider: "google", idToken: tokens.id_token, nonce: nonce, givenName: nil)
    }

    // MARK: Yardımcılar

    static func randomString(length: Int = 32) -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._")
        var generator = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in alphabet.randomElement(using: &generator)! })
    }

    static func sha256(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

extension SignInService: ASAuthorizationControllerDelegate {
    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        MainActor.assumeIsolated {
            appleContinuation?.resume(returning: authorization)
            appleContinuation = nil
        }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        MainActor.assumeIsolated {
            let cancelled = (error as? ASAuthorizationError)?.code == .canceled
            appleContinuation?.resume(throwing: cancelled ? SignInError.cancelled : SignInError.failed)
            appleContinuation = nil
        }
    }
}

extension SignInService: ASAuthorizationControllerPresentationContextProviding, ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated { Self.keyWindow() }
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated { Self.keyWindow() }
    }

    private static func keyWindow() -> UIWindow {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow) ?? UIWindow()
    }
}
