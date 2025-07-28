import Foundation

/// Service for clock-in and clock-out requests to the backend
struct SessionService {
    private static let baseURL = "http://172.16.42.23:3000/session"

    /// Clock-in at the given location ID
    static func clockIn(locationId: Int, completion: ((Result<Void, Error>) -> Void)? = nil) {
        AuthManager.shared.withFreshTokens { token, error in
            if let err = error {
                completion?(.failure(err))
                return
            }
            guard let token = token,
                  let url = URL(string: "\(baseURL)/clockIn/\(locationId)")
            else {
                let err = NSError(domain: "", code: -1,
                                  userInfo: [NSLocalizedDescriptionKey: "Invalid clockIn URL or missing token"])
                completion?(.failure(err))
                return
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            URLSession.shared.dataTask(with: request) { _, response, error in
                if let error = error {
                    completion?(.failure(error))
                } else if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                    completion?(.success(()))
                } else {
                    let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                    let err = NSError(domain: "", code: code,
                                      userInfo: [NSLocalizedDescriptionKey: "Unexpected status code: \(code)"])
                    completion?(.failure(err))
                }
            }.resume()
        }
    }

    /// Clock-out for the current session
    static func clockOut(completion: ((Result<Void, Error>) -> Void)? = nil) {
        AuthManager.shared.withFreshTokens { token, error in
            if let err = error {
                completion?(.failure(err))
                return
            }
            guard let token = token,
                  let url = URL(string: "\(baseURL)/clockOut")
            else {
                let err = NSError(domain: "", code: -1,
                                  userInfo: [NSLocalizedDescriptionKey: "Invalid clockOut URL or missing token"])
                completion?(.failure(err))
                return
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            URLSession.shared.dataTask(with: request) { _, response, error in
                if let error = error {
                    completion?(.failure(error))
                } else if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                    completion?(.success(()))
                } else {
                    let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                    let err = NSError(domain: "", code: code,
                                      userInfo: [NSLocalizedDescriptionKey: "Unexpected status code: \(code)"])
                    completion?(.failure(err))
                }
            }.resume()
        }
    }
    
    static func deleteSession(SessionID: Int, completion: ((Result<Void, Error>) -> Void)? = nil) {
        AuthManager.shared.withFreshTokens { token, error in
            if let err = error {
                completion?(.failure(err))
                return
            }
            guard let token = token,
                  let url = URL(string: "http://172.16.42.23:3000/session/\(SessionID)")
            else {
                let err = NSError(domain: "", code: -1,
                                  userInfo: [NSLocalizedDescriptionKey: "Invalid ddelete URL or missing token"])
                completion?(.failure(err))
                return
            }

            var request = URLRequest(url: url)
            request.httpMethod = "DELETE"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            URLSession.shared.dataTask(with: request) { _, response, error in
                if let error = error {
                    completion?(.failure(error))
                } else if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                    completion?(.success(()))
                } else {
                    let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                    let err = NSError(domain: "", code: code,
                                      userInfo: [NSLocalizedDescriptionKey: "Unexpected status code: \(code)"])
                    completion?(.failure(err))
                }
            }.resume()
        }
    }
    
    
    static func editSession(
        sessionId: Int,
        locationId: Int,
        checkIn: Date,
        checkOut: Date?,
        completion: ((Result<Void, Error>) -> Void)? = nil
      ) {
        guard let url = URL(string: "http://172.16.42.23:3000/session/\(sessionId)") else {
          completion?(.failure(NSError(
            domain: "", code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Invalid editSession URL"]
          )))
          return
        }
        // DTO aufbauen
        var dto: [String: Any] = [
          "location": locationId,
          "checkinTimestamp": ISO8601DateFormatter()
            .string(from: checkIn)
        ]
        if let out = checkOut {
          dto["checkoutTimestamp"] = ISO8601DateFormatter().string(from: out)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Auth-Header
        AuthManager.shared.withFreshTokens { token, error in
          guard let token = token else {
            completion?(.failure(error!)); return
          }
          request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
          // JSON-Body
          request.httpBody = try? JSONSerialization.data(withJSONObject: dto)

          URLSession.shared.dataTask(with: request) { _, resp, err in
            if let err = err {
              completion?(.failure(err))
            } else if let http = resp as? HTTPURLResponse, 200...299 ~= http.statusCode {
              completion?(.success(()))
            } else {
              let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
              completion?(.failure(NSError(
                domain: "", code: code,
                userInfo:[NSLocalizedDescriptionKey:"Unexpected status code: \(code)"]
              )))
            }
          }.resume()
        }
      }

    


    static func getCurrentLocation(
          userId: Int,
          completion: @escaping (Result<(locationId: Int, locationName: String)?, Error>) -> Void
        ) {
            AuthManager.shared.withFreshTokens { token, error in
                guard let token = token else {
                    return completion(.failure(error!))
                }
                let url = URL(string: "http://172.16.42.23:3000/web/user-current-location/\(userId)")!
                var req = URLRequest(url: url)
                req.httpMethod = "GET"
                req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

                URLSession.shared.dataTask(with: req) { data, resp, err in
                    if let err = err {
                        return completion(.failure(err))
                    }
                    guard let data = data,
                          let json = try? JSONSerialization.jsonObject(with: data) as? [String:Any]
                    else {
                        return completion(.failure(NSError(
                          domain:"", code:-1,
                          userInfo:[NSLocalizedDescriptionKey:"Invalid response"]
                        )))
                    }
                    // currentLocation kann nil oder Dictionary sein
                    if let cur = json["currentLocation"] as? [String:Any],
                       let id   = cur["locationId"]   as? Int,
                       let name = cur["locationName"] as? String {
                        completion(.success((locationId:id, locationName:name)))
                    } else {
                        completion(.success(nil))
                    }
                }.resume()
            }
        }

    static func fetchStatistics(
        userId: Int,
        completion: @escaping (Result<[Statistic], Error>) -> Void
    ) {
        AuthManager.shared.withFreshTokens { token, error in
            guard let token = token else {
                return completion(.failure(error!))
            }
            let url = URL(string: "http://172.16.42.23:3000/app-request/statistics/\(userId)")!
            var req = URLRequest(url: url)
            req.httpMethod = "GET"
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            URLSession.shared.dataTask(with: req) { data, resp, err in
                if let err = err { return completion(.failure(err)) }
                guard let data = data else {
                    return completion(.failure(NSError(
                        domain: "", code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "No data"]
                    )))
                }
                do {
                    let decoder = JSONDecoder()
                    let formatter = DateFormatter()
                    formatter.locale = Locale(identifier: "en_US_POSIX")
                    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
                    decoder.dateDecodingStrategy = .formatted(formatter)
                    let stats = try decoder.decode([Statistic].self, from: data)
                    completion(.success(stats))
                } catch {
                    completion(.failure(error))
                }
            }.resume()
        }
    }
}
