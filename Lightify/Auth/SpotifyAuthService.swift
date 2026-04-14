//
//  SpotifyAuthService.swift
//  Lightify
//

import AuthenticationServices
import Foundation

@MainActor
final class SpotifyAuthService: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var currentSession: ASWebAuthenticationSession?

    func presentationAnchor(for _: ASWebAuthenticationSession) -> ASPresentationAnchor {
        ASPresentationAnchor()
    }

    /// Starts browser OAuth. Call from a button action; result includes tokens saved to Keychain by caller if desired.
    func signIn() async throws -> StoredSpotifySession {
        let verifier = PKCE.generateVerifier()
        let challenge = PKCE.challenge(from: verifier)
        let state = Self.randomState()

        guard var components = URLComponents(url: SpotifyConfig.authorizeURL, resolvingAgainstBaseURL: false) else {
            throw SpotifyAuthError.invalidConfiguration
        }
        components.queryItems = [
            URLQueryItem(name: "client_id", value: SpotifyConfig.clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: SpotifyConfig.redirectURI),
            URLQueryItem(name: "scope", value: SpotifyConfig.scopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "state", value: state),
        ]
        guard let url = components.url else {
            throw SpotifyAuthError.invalidConfiguration
        }

        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: "lightify"
            ) { [weak self] callbackURL, error in
                guard let self else {
                    continuation.resume(throwing: SpotifyAuthError.cancelled)
                    return
                }
                Task { @MainActor in
                    self.currentSession = nil
                    if let error {
                        let authErr = error as? ASWebAuthenticationSessionError
                        if authErr?.code == .canceledLogin {
                            continuation.resume(throwing: SpotifyAuthError.cancelled)
                        } else {
                            continuation.resume(throwing: error)
                        }
                        return
                    }
                    guard let callbackURL else {
                        continuation.resume(throwing: SpotifyAuthError.noCallbackURL)
                        return
                    }
                    do {
                        let session = try await self.exchangeCode(from: callbackURL, verifier: verifier, expectedState: state)
                        continuation.resume(returning: session)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.currentSession = session
            if !session.start() {
                continuation.resume(throwing: SpotifyAuthError.sessionStartFailed)
            }
        }
    }

    private func exchangeCode(from callbackURL: URL, verifier: String, expectedState: String) async throws -> StoredSpotifySession {
        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false) else {
            throw SpotifyAuthError.invalidCallback
        }
        var code: String?
        var returnedState: String?
        var errorDescription: String?
        for item in components.queryItems ?? [] {
            switch item.name {
            case "code": code = item.value
            case "state": returnedState = item.value
            case "error": errorDescription = item.value
            default: break
            }
        }
        if let errorDescription {
            throw SpotifyAuthError.oauthError(errorDescription)
        }
        guard let code, !code.isEmpty else {
            throw SpotifyAuthError.missingCode
        }
        guard returnedState == expectedState else {
            throw SpotifyAuthError.stateMismatch
        }

        var request = URLRequest(url: SpotifyConfig.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": SpotifyConfig.redirectURI,
            "client_id": SpotifyConfig.clientID,
            "code_verifier": verifier,
        ]
        request.httpBody = Self.formURLEncoded(body).data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SpotifyAuthError.badResponse
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw SpotifyAuthError.tokenExchangeFailed(http.statusCode, msg)
        }

        let decoded = try JSONDecoder().decode(SpotifyTokenResponse.self, from: data)
        guard let refresh = decoded.refreshToken else {
            throw SpotifyAuthError.missingRefreshToken
        }
        let expiry = Date().addingTimeInterval(TimeInterval(decoded.expiresIn) - 60)
        return StoredSpotifySession(
            accessToken: decoded.accessToken,
            refreshToken: refresh,
            accessTokenExpiry: expiry,
            grantedScopes: decoded.scope
        )
    }

    func refreshSession(_ session: StoredSpotifySession) async throws -> StoredSpotifySession {
        var request = URLRequest(url: SpotifyConfig.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = [
            "grant_type": "refresh_token",
            "refresh_token": session.refreshToken,
            "client_id": SpotifyConfig.clientID,
        ]
        request.httpBody = Self.formURLEncoded(body).data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SpotifyAuthError.badResponse
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw SpotifyAuthError.tokenExchangeFailed(http.statusCode, msg)
        }

        let decoded = try JSONDecoder().decode(SpotifyTokenResponse.self, from: data)
        let newRefresh = decoded.refreshToken ?? session.refreshToken
        let expiry = Date().addingTimeInterval(TimeInterval(decoded.expiresIn) - 60)
        return StoredSpotifySession(
            accessToken: decoded.accessToken,
            refreshToken: newRefresh,
            accessTokenExpiry: expiry,
            grantedScopes: decoded.scope ?? session.grantedScopes
        )
    }

    private static func formURLEncoded(_ dict: [String: String]) -> String {
        dict.map { key, value in
            let k = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
            let v = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
            return "\(k)=\(v)"
        }.joined(separator: "&")
    }

    private static func randomState() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

enum SpotifyAuthError: LocalizedError {
    case invalidConfiguration
    case cancelled
    case noCallbackURL
    case invalidCallback
    case missingCode
    case stateMismatch
    case oauthError(String)
    case badResponse
    case tokenExchangeFailed(Int, String)
    case missingRefreshToken
    case sessionStartFailed

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return "Spotify OAuth configuration is invalid."
        case .cancelled:
            return "Sign in was cancelled."
        case .noCallbackURL:
            return "No redirect URL returned from Spotify."
        case .invalidCallback:
            return "Invalid OAuth callback URL."
        case .missingCode:
            return "Authorization code missing from callback."
        case .stateMismatch:
            return "OAuth state did not match (possible CSRF)."
        case let .oauthError(code):
            return "Spotify OAuth error: \(code)"
        case .badResponse:
            return "Unexpected response from Spotify."
        case let .tokenExchangeFailed(status, body):
            return "Token exchange failed (\(status)): \(body)"
        case .missingRefreshToken:
            return "No refresh token returned. Try signing in again."
        case .sessionStartFailed:
            return "Could not start sign-in session."
        }
    }
}
