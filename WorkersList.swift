//
//  WorkersListView.swift
//  YourAppName
//
//  Created by You on YYYY/MM/DD.
//

import SwiftUI

/// Modell für deine Locations (aus dem Backend)
struct LocationModel: Codable, Identifiable {
    let locationID: Int
    let locationName: String
    
    // Für SwiftUI Identifiable
    var id: Int { locationID }
}

struct WorkersListView: View {
    @State private var locations: [LocationModel] = []
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if let error = errorMessage {
                    Text("Fehler: \(error)")
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding()
                } else if locations.isEmpty {
                    ProgressView("Lade Standorte…")
                } else {
                    List(locations) { loc in
                        Text(loc.locationName)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Standorte")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Refresh") {
                        loadLocations()
                    }
                }
            }
        }
        .onAppear(perform: loadLocations)
    }

    private func loadLocations() {
        errorMessage = nil
        locations = []

        // localhost im Simulator, LAN‑IP auf echtem Gerät
        #if targetEnvironment(simulator)
        let host = "localhost"
        #else
        let host = "172.16.42.23"
        #endif

        guard let url = URL(string: "http://\(host):3000/web/allLocations") else {
            errorMessage = "Ungültige URL"
            return
        }

        APIClient.shared.getJSON(url) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let json):
                    guard let arr = json as? [[String: Any]] else {
                        errorMessage = "Ungültiges JSON-Format"
                        return
                    }
                    locations = arr.compactMap { dict in
                        guard
                            let id   = dict["locationID"]  as? Int,
                            let name = dict["locationName"] as? String
                        else { return nil }
                        return LocationModel(locationID: id,
                                             locationName: name)
                    }
                case .failure(let err):
                    if let urlErr = err as? URLError {
                        errorMessage = "Network Error: \(urlErr.code)"
                        print("🔴 URLError:", urlErr)
                    } else {
                        errorMessage = err.localizedDescription
                        print("🔴 Error:", err)
                    }
                }
            }
        }
    }
}

struct WorkersListView_Previews: PreviewProvider {
    static var previews: some View {
        WorkersListView()
    }
}
