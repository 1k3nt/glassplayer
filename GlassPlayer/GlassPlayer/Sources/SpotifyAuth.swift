import Foundation
import AuthenticationServices
import CryptoKit
import UIKit

enum SpotifyConfig {
    /// 1. Go to developer.spotify.com/dashboard and create an app.
    /// 2. Add this exact Redirect URI to it:  glassplayer://callback
    /// 3. Paste its Client ID below (or set the SPOTIFY_CLIENT_ID repo variable for the GitHub build).
    static let clientID = "SPOTIFY_CLIENT_ID_HERE"
    static let redirectScheme = "glassplayer"
    static let redirectURI = "glassplayer://callback"
    static let scopes = "user-read-playback-state user-modify-playback-state user-read-currently-playing"

    /// Spotify client IDs are 32 characters, so anything else means "not filled in yet".
    static var isConfigured: Bool { clientID.count == 32 }
}

/// Authorization Code + PKCE (no client secret ever lives in the app).
@MainActor
final class SpotifyAuth: NSObject, ASWebAuthenticationPresentationContextProviding {
    private(set) var isSignedIn = Keychain.get("refresh") != nil
    private var accessToken: String?
    private var expiry = Date.distantPast
    private var session: ASWebAuthenticationSession?

    func signIn() async throws {
        let verifier = Self.randomString(64)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL

        var c = URLComponents(string: "https://accounts.spotify.com/authorize")!
        c.queryItems = [
            URLQueryItem(name: "client_id", value: SpotifyConfig.clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: SpotifyConfig.redirectURI),
            URLQueryItem(name: "scope", value: SpotifyConfig.scopes),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge),
        ]
        let authURL = c.url!

        let callback: URL = try await withCheckedThrowingContinuation { cont in
            let s = ASWebAuthenticationSession(url: authURL, callbackURLScheme: SpotifyConfig.redirectScheme) { url, error in
                if let url { cont.resume(returning: url) }
                else { cont.resume(throwing: error ?? URLError(.cancelled)) }
            }
            s.presentationContextProvider = self
            self.session = s
            s.start()
        }

        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems
        guard let code = items?.first(where: { $0.name == "code" })?.value else {
            throw URLError(.badServerResponse)
        }
        try await tokenRequest([
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": SpotifyConfig.redirectURI,
            "client_id": SpotifyConfig.clientID,
            "code_verifier": verifier,
        ])
    }

    func signOut() {
        Keychain.delete("refresh")
        accessToken = nil
        isSignedIn = false
    }

    func validToken() async throws -> String {
        if let t = accessToken, Date() < expiry { return t }
        guard let refresh = Keychain.get("refresh") else {
            isSignedIn = false
            throw URLError(.userAuthenticationRequired)
        }
        do {
            try await tokenRequest([
                "grant_type": "refresh_token",
                "refresh_token": refresh,
                "client_id": SpotifyConfig.clientID,
            ])
        } catch {
            signOut()
            throw error
        }
        return accessToken ?? ""
    }

    private func tokenRequest(_ params: [String: String]) async throws {
        var req = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = params.map { "\($0.key)=\($0.value.formEncoded)" }
            .joined(separator: "&").data(using: .utf8)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.userAuthenticationRequired)
        }
        struct TokenResponse: Decodable {
            let access_token: String
            let expires_in: Double
            let refresh_token: String?
        }
        let t = try JSONDecoder().decode(TokenResponse.self, from: data)
        accessToken = t.access_token
        expiry = Date().addingTimeInterval(t.expires_in - 30)
        if let r = t.refresh_token { Keychain.set(r, for: "refresh") }
        isSignedIn = true
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        return scene?.keyWindow ?? ASPresentationAnchor()
    }

    private static func randomString(_ n: Int) -> String {
        let chars = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return String((0..<n).map { _ in chars.randomElement()! })
    }
}

private extension Data {
    var base64URL: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private extension String {
    var formEncoded: String {
        addingPercentEncoding(withAllowedCharacters: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))) ?? self
    }
}

enum Keychain {
    private static func base(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "GlassPlayer",
         kSecAttrAccount as String: key]
    }
    static func set(_ value: String, for key: String) {
        SecItemDelete(base(key) as CFDictionary)
        var add = base(key)
        add[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(add as CFDictionary, nil)
    }
    static func get(_ key: String) -> String? {
        var q = base(key)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func delete(_ key: String) {
        SecItemDelete(base(key) as CFDictionary)
    }
}
