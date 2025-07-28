//
//  APIClient.swift
//  YourAppName
//
//  Created by You on YYYY/MM/DD.
//

import Foundation

/// HTTP-Client mit zwei Varianten:
///  - get<T: Decodable> für typisierte Decodable-Modelle
///  - getJSON für beliebiges JSON via JSONSerialization
class APIClient {
    static let shared = APIClient()

    /// Test-Call: JSON als Any (Dictionary oder Array)
    func getJSON(_ url: URL,
                 completion: @escaping (Result<Any, Error>) -> Void) {
        AuthManager.shared.withFreshTokens { token, error in
            guard let token = token, error == nil else {
                return completion(.failure(error ?? NSError(domain: "", code: -1)))
            }
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(token)",
                             forHTTPHeaderField: "Authorization")

            URLSession.shared.dataTask(with: request) { data, _, err in
                if let err = err { return completion(.failure(err)) }
                guard let data = data else {
                    return completion(.failure(NSError(domain: "", code: -1)))
                }
                do {
                    let json = try JSONSerialization.jsonObject(with: data, options: [])
                    completion(.success(json))
                } catch {
                    completion(.failure(error))
                }
            }.resume()
        }
    }
}
