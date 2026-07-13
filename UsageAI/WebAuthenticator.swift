import Foundation
import UIKit
import AuthenticationServices

/// Drives the interactive OAuth authorization step.
///
/// Two shapes are supported:
///  - **Scheme callback** (e.g. Google): `ASWebAuthenticationSession` opens the
///    authorize URL and intercepts the redirect to our custom scheme.
///  - **Manual code entry** (e.g. Anthropic's first-party client, whose redirect
///    can't be captured): the caller opens the authorize URL in the browser and
///    pastes back the code shown on the callback page, then calls `exchange`.
@MainActor
final class WebAuthenticator: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {

    enum AuthError: LocalizedError {
        case cannotStart, cancelled, noCode, stateMismatch, notConfigured

        var errorDescription: String? {
            switch self {
            case .cannotStart: return "Couldn't start the sign-in session"
            case .cancelled: return "Sign-in was cancelled"
            case .noCode: return "No authorization code was returned"
            case .stateMismatch: return "Security check failed (state mismatch)"
            case .notConfigured: return "This provider needs an OAuth client ID first"
            }
        }
    }

    private var session: ASWebAuthenticationSession?

    // MARK: Scheme-callback flow (Google)

    func login(config: OAuthConfig) async throws -> OAuthToken {
        guard config.isConfigured else { throw AuthError.notConfigured }
        let pkce = PKCE()
        let state = PKCE.randomURLSafeString(byteCount: 16)
        let authURL = config.buildAuthorizeURL(pkce: pkce, state: state)

        let callbackURL: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: config.callbackScheme
            ) { url, error in
                if let url {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(throwing: error ?? AuthError.cancelled)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            if !session.start() { continuation.resume(throwing: AuthError.cannotStart) }
        }

        let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)
        guard let code = components?.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw AuthError.noCode
        }
        if let returnedState = components?.queryItems?.first(where: { $0.name == "state" })?.value,
           returnedState != state {
            throw AuthError.stateMismatch
        }
        return try await OAuthClient.exchange(config: config, code: code, verifier: pkce.verifier)
    }

    // MARK: Manual-code flow (Anthropic)

    /// A pending manual authorization: open `url`, then pass the pasted code to
    /// `exchange(config:manual:code:)`.
    struct ManualAuthorization {
        let url: URL
        let pkce: PKCE
        let state: String
    }

    func manualAuthorization(config: OAuthConfig) -> ManualAuthorization {
        let pkce = PKCE()
        let state = PKCE.randomURLSafeString(byteCount: 16)
        return ManualAuthorization(url: config.buildAuthorizeURL(pkce: pkce, state: state),
                                   pkce: pkce,
                                   state: state)
    }

    func exchange(config: OAuthConfig,
                  manual: ManualAuthorization,
                  code: String) async throws -> OAuthToken {
        try await OAuthClient.exchange(config: config,
                                       code: code.trimmingCharacters(in: .whitespacesAndNewlines),
                                       verifier: manual.pkce.verifier)
    }

    // MARK: ASWebAuthenticationPresentationContextProviding

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        return scene?.keyWindow ?? ASPresentationAnchor()
    }
}

private extension UIWindowScene {
    var keyWindow: UIWindow? { windows.first { $0.isKeyWindow } ?? windows.first }
}
