//
//  AuthManager.swift
//  YourAppName
//
//  Created by You on YYYY/MM/DD.
//

import Foundation
import AuthenticationServices
import UIKit
import Combine
import CryptoKit
import WebKit

/// Verwaltet den Keycloak‑Login via Authorization Code Flow **mit PKCE** (Public Client)
class AuthManager: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = AuthManager()

    @Published var isAuthenticated = false

    private var webAuthSession: ASWebAuthenticationSession?
    private var codeVerifier: String?
    private let idTokenKey = "idToken"

    // Keychain‑Keys
    private let service           = "com.diamir.receptionist"
    private let accessTokenKey    = "accessToken"
    private let refreshTokenKey   = "refreshToken"
    private let expirationDateKey = "expirationDate"

    // MARK: – Initialization

    private override init() {
        super.init()
        restoreAuthState()
    }

    /// Prüft beim Start auf vorhandene, gültige Tokens
    private func restoreAuthState() {
        withFreshTokens { token, error in
            DispatchQueue.main.async {
                self.isAuthenticated = (token != nil && error == nil)
            }
        }
    }

    // MARK: – Schritt 1: Login mit PKCE starten

    func startLogin() {
        // 1) Erzeuge PKCE-Code-Verifier & Challenge
        let verifier = Self.generateCodeVerifier()
        codeVerifier = verifier
        let challenge = Self.codeChallenge(from: verifier)

        // 2) Baue Auth‑URL
        var comps = URLComponents(string:
            "https://sso.diamir.dev/realms/nein/protocol/openid-connect/auth"
        )!
        comps.queryItems = [
            URLQueryItem(name: "client_id",            value: "receptionist-dev-public"),
            URLQueryItem(name: "redirect_uri",         value: "com.diamir.receptionist:/oauth2redirect"),
            URLQueryItem(name: "response_type",        value: "code"),
            URLQueryItem(name: "scope",                value: "openid profile"),
            URLQueryItem(name: "code_challenge",       value: challenge),
            URLQueryItem(name: "code_challenge_method",value: "S256"),
            URLQueryItem(name: "prompt",               value: "login")
        ]
        guard let authURL = comps.url else {
            print("🔴 Ungültige Auth-URL")
            return
        }

        // 3) Starte ASWebAuthenticationSession
        webAuthSession = ASWebAuthenticationSession(
            url: authURL,
            callbackURLScheme: "com.diamir.receptionist"
        ) { callbackURL, error in
            if let error = error {
                print("🔴 Auth-Error:", error.localizedDescription)
                return
            }
            guard
                let callbackURL = callbackURL,
                let code = URLComponents(string: callbackURL.absoluteString)?
                    .queryItems?.first(where: { $0.name == "code" })?.value
            else {
                print("🔴 Kein Code in Callback-URL")
                return
            }
            print("✅ Authorization Code erhalten:", code)
            self.exchangeCodeForToken(code: code)
        }
        if #available(iOS 13.0, *) {
            webAuthSession?.prefersEphemeralWebBrowserSession = true
        }
        webAuthSession?.presentationContextProvider = self
        webAuthSession?.start()
    }

    // MARK: – Schritt 2: Code gegen Tokens tauschen

    private func exchangeCodeForToken(code: String) {
        guard let verifier = codeVerifier else { return }

        let tokenURL = URL(string:
            "https://sso.diamir.dev/realms/nein/protocol/openid-connect/token"
        )!
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        let params: [String: String] = [
            "grant_type":    "authorization_code",
            "client_id":     "receptionist-dev-public",
            "code":          code,
            "redirect_uri":  "com.diamir.receptionist:/oauth2redirect",
            "code_verifier": verifier
        ]
        request.httpBody = params
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)
        request.setValue("application/x-www-form-urlencoded",
                         forHTTPHeaderField: "Content-Type")

        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error = error {
                print("🔴 Token-Request Error:", error.localizedDescription)
                return
            }
            guard
                let data = data,
                let json = try? JSONSerialization.jsonObject(with: data) as? [String:Any],
                let accessToken  = json["access_token"]  as? String,
                let refreshToken = json["refresh_token"] as? String,
                let idToken      = json["id_token"]     as? String,
                let expiresIn    = json["expires_in"]    as? Int
            else {
                print("🔴 Unerwartetes Token‑JSON")
                return
            }

            // 3) Speichere Tokens in Keychain
            KeychainHelper.standard.save(accessToken,
                                        service: self.service,
                                        account: self.accessTokenKey)
            KeychainHelper.standard.save(refreshToken,
                                        service: self.service,
                                        account: self.refreshTokenKey)
            let expiryDate = Date().addingTimeInterval(TimeInterval(expiresIn))
            KeychainHelper.standard.save(
                String(expiryDate.timeIntervalSince1970),
                service: self.service,
                account: self.expirationDateKey
            )

            print("✅ Tokens gespeichert (expires in \(expiresIn)s)")
            print(accessToken)
            DispatchQueue.main.async { self.isAuthenticated = true }
        }.resume()
    }

    // MARK: – Schritt 3: Gültiges Access‑Token liefern (inkl. Refresh)

    func withFreshTokens(
        completion: @escaping (_ accessToken: String?, _ error: Error?) -> Void
    ) {
        // Lese aus Keychain
        guard
            let token     = KeychainHelper.standard.read(service: service, account: accessTokenKey),
            let expString = KeychainHelper.standard.read(service: service, account: expirationDateKey),
            let expTime   = TimeInterval(expString)
        else {
            return completion(nil, NSError(domain:"", code:-1,
                                           userInfo:[NSLocalizedDescriptionKey:"kein Token"]))
        }
        let expiry = Date(timeIntervalSince1970: expTime)
        if Date() < expiry {
            // Token noch gültig
            return completion(token, nil)
        }
        // Token abgelaufen → Refresh
        guard let refresh = KeychainHelper.standard.read(service: service, account: refreshTokenKey)
        else {
            return completion(nil, NSError(domain:"", code:-1,
                                           userInfo:[NSLocalizedDescriptionKey:"kein Refresh-Token"]))
        }

        let tokenURL = URL(string:
            "https://sso.diamir.dev/realms/nein/protocol/openid-connect/token"
        )!
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        let params: [String: String] = [
            "grant_type":    "refresh_token",
            "client_id":     "receptionist-dev-public",
            "refresh_token": refresh
        ]
        request.httpBody = params
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)
        request.setValue("application/x-www-form-urlencoded",
                         forHTTPHeaderField: "Content-Type")

        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error = error {
                return completion(nil, error)
            }
            guard
                let data = data,
                let json = try? JSONSerialization.jsonObject(with: data) as? [String:Any],
                let newToken   = json["access_token"]  as? String,
                let newRefresh = json["refresh_token"] as? String,
                let expiresIn  = json["expires_in"]    as? Int
            else {
                return completion(nil, NSError(domain:"", code:-1))
            }

            // Speichere neu
            KeychainHelper.standard.save(newToken,
                                        service: self.service,
                                        account: self.accessTokenKey)
            KeychainHelper.standard.save(newRefresh,
                                        service: self.service,
                                        account: self.refreshTokenKey)
            let newExpiry = Date().addingTimeInterval(TimeInterval(expiresIn))
            KeychainHelper.standard.save(
                String(newExpiry.timeIntervalSince1970),
                service: self.service,
                account: self.expirationDateKey
            )

            completion(newToken, nil)
        }.resume()
    }

    // MARK: – PKCE Hilfsfunktionen

    /// Erzeugt einen zufälligen Code Verifier
    private static func generateCodeVerifier() -> String {
        let data = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
        return data.base64URLEncodedString()
    }

    /// Erzeugt den SHA256-basierenden Code Challenge
    private static func codeChallenge(from verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URLEncodedString()
    }

    // MARK: – Logout

    func logout() {
        // 1) Lese jetzt idToken, nicht accessToken!
        guard
          let idToken = KeychainHelper.standard.read(service: service, account: idTokenKey),
          let endSessionURL = URL(string:
            "https://sso.diamir.dev/realms/nein/protocol/openid-connect/logout"
          )
        else {
          clearLocalSession()
          return
        }

        var comps = URLComponents(url: endSessionURL, resolvingAgainstBaseURL: false)!
        comps.queryItems = [
          .init(name: "id_token_hint",            value: idToken),
          .init(name: "post_logout_redirect_uri", value: "com.diamir.receptionist:/oauth2redirect")
        ]
        let logoutURL = comps.url!

        let session = ASWebAuthenticationSession(
          url: logoutURL,
          callbackURLScheme: "com.diamir.receptionist"
        ) { _, _ in
          self.clearLocalSession()
          self.clearWebviewCookies()
        }
        // keine Ephemere Session verwenden
        session.prefersEphemeralWebBrowserSession = false
        session.start()
    }

    /// Löscht nur lokal gespeicherte Tokens und setzt isAuthenticated back to false
    private func clearLocalSession() {
        KeychainHelper.standard.delete(service: service, account: accessTokenKey)
        KeychainHelper.standard.delete(service: service, account: refreshTokenKey)
        KeychainHelper.standard.delete(service: service, account: expirationDateKey)
        DispatchQueue.main.async { self.isAuthenticated = false }
    }

    /// Entfernt alle Cookies/Web‑Daten für dein Keycloak‑Realm
    private func clearWebviewCookies() {
        // 1) HTTPCookieStorage
        let cookieStore = HTTPCookieStorage.shared
        cookieStore.cookies?
          .filter { $0.domain.contains("sso.diamir.dev") }
          .forEach(cookieStore.deleteCookie)

        // 2) WKWebsiteDataStore
        let dataStore = WKWebsiteDataStore.default()
        dataStore.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
            let ssoRecords = records.filter {
                $0.displayName.contains("sso.diamir.dev")
            }
            dataStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                                 for: ssoRecords) {
                print("🗑️ Keycloak Cookies und Web‑Daten gelöscht")
            }
        }
    }

    // MARK: – Presentation Context (for ASWebAuthenticationSession)

    func presentationAnchor(
        for session: ASWebAuthenticationSession
    ) -> ASPresentationAnchor {
        UIApplication.shared.windows.first { $0.isKeyWindow }!
    }
}

// MARK: – Data‑Extension für Base64URL

private extension Data {
    func base64URLEncodedString() -> String {
        self.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "="))
    }
}
