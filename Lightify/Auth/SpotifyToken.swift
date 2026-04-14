//
//  SpotifyToken.swift
//  Lightify
//

import Foundation

struct SpotifyTokenResponse: Codable, Sendable {
    let accessToken: String
    let tokenType: String
    let expiresIn: Int
    let refreshToken: String?
    let scope: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case scope
    }
}

struct StoredSpotifySession: Codable, Sendable {
    var accessToken: String
    var refreshToken: String
    var accessTokenExpiry: Date
    /// Space-separated scopes from the last token response (`nil` = session saved before scopes were tracked).
    var grantedScopes: String?

    /// Whether this session includes the scopes currently required by the app.
    func includesRequiredScopes() -> Bool {
        let required = Set(SpotifyConfig.scopes)
        let parts = Set(
            (grantedScopes ?? "")
                .split(separator: " ")
                .map(String.init)
        )
        return required.isSubset(of: parts)
    }
}
