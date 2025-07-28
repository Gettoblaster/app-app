//
//  VerlaufView.swift
//  YourAppName
//
//  Created by You on YYYY/MM/DD.
//

import SwiftUI

// MARK: – Session-Model passend zum Backend JSON
struct Session: Identifiable, Decodable {
    let sessionID: Int
    let startTime: Date
    let endTime: Date?
    let locationName: String
    let locationId: Int

    var id: Int { sessionID }

    enum CodingKeys: String, CodingKey {
        case sessionID       = "sessionid"
        case startTime       = "checkintimestamp"
        case endTime         = "checkouttimestamp"
        case locationName    = "locationname"
        case locationId      = "locationId"
    }
}

// MARK: – Modell für verfügbare Locations
struct AvailableLocation: Identifiable, Decodable {
    let id: Int
    let name: String
}

// MARK: – Einzelnes Check-In/Check-Out Ereignis
struct CheckEvent: Identifiable {
    let id = UUID()
    var type: EventType
    var date: Date
    var building: String

    enum EventType: String, CaseIterable {
        case checkIn  = "Check-In"
        case checkOut = "Check-Out"

        var iconName: String { self == .checkIn ? "arrow.down.circle.fill" : "arrow.up.circle.fill" }
        var color: Color { self == .checkIn ? .green : .red }
    }
}

// MARK: – Gruppe von Events zu einer Session
struct SessionGroup: Identifiable {
    let id: Int
    var events: [CheckEvent]
}

// MARK: – Historie eines Monats
struct MonthHistory: Identifiable {
    let id = UUID()
    let monthName: String
    var sessions: [SessionGroup]
}

// MARK: – Haupt-View
struct VerlaufView: View {
    @State private var historyByMonth: [MonthHistory] = []
    @State private var availableLocations: [AvailableLocation] = []
    @State private var monthIndex = 0

    // JSONDecoder mit ISO-Datum
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        let isoFormatter = DateFormatter()
        isoFormatter.locale = Locale(identifier: "en_US_POSIX")
        isoFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        isoFormatter.timeZone = TimeZone.current
        d.dateDecodingStrategy = .formatted(isoFormatter)
        return d
    }()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                pager
            }
            .navigationTitle("Verlauf")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear(perform: loadData)
        }
    }

    // Monatsnavigation
    private var header: some View {
        HStack {
            Button { if monthIndex > 0 { monthIndex -= 1 } } label: {
                Image(systemName: "chevron.left").font(.title2)
            }
            Spacer()
            Text(historyByMonth.isEmpty ? "Lade…" : historyByMonth[monthIndex].monthName)
                .font(.title2).fontWeight(.semibold)
            Spacer()
            Button { if monthIndex + 1 < historyByMonth.count { monthIndex += 1 } } label: {
                Image(systemName: "chevron.right").font(.title2)
            }
        }
        .padding()
    }

    // TabView mit Sessions
    private var pager: some View {
        TabView(selection: $monthIndex) {
            ForEach(historyByMonth.indices, id: \.self) { idx in
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(historyByMonth[idx].sessions) { group in
                            NavigationLink(
                                destination: EditSessionView(
                                    sessionGroup: binding(for: group, in: idx),
                                    locations: availableLocations
                                )
                            ) {
                                SessionCard(group: group)
                            }
                        }
                    }
                    .padding()
                }
                .tag(idx)
            }
        }
        .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
    }

    // Binding-Helper
    private func binding(for group: SessionGroup, in month: Int) -> Binding<SessionGroup> {
        let index = historyByMonth[month].sessions.firstIndex { $0.id == group.id }!
        return $historyByMonth[month].sessions[index]
    }

    // Zeit-Formatter für Display
    public static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "HH:mm"
        f.timeZone = TimeZone.current
        return f
    }()

    // MARK: – Daten laden
    private func loadData() {
        // 1) User-ID holen
        print("🚀 onAppear: loadData() aufgerufen")
        guard let userURL = URL(string: "http://172.16.42.23:3000/user/me") else { return }
        APIClient.shared.getJSON(userURL) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let json):
                    guard
                        let dict = json as? [String: Any],
                        let userId = dict["id"] as? Int
                    else { return }
                    // nach ID die History und Locations laden
                    fetchHistory(userId: userId)
                    fetchLocations()
                case .failure:
                    break
                }
            }
        }
    }

    // History vom Backend
    private func fetchHistory(userId: Int) {
        guard let url = URL(string: "http://172.16.42.23:3000/web/user-history/\(userId)") else {
            print("🔴 Ungültige History-URL")
            return
        }
        print("➡️ Lade History von:", url)
        APIClient.shared.getJSON(url) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let json):
                    // Debug-Ausgabe
                    print("✅ History-Rohdaten:", json)
                    guard let arr = json as? [[String: Any]] else {
                        print("🔴 History: JSON ist kein Array von Dicts")
                        return
                    }
                    do {
                        // serialisiere & decode
                        let data = try JSONSerialization.data(withJSONObject: arr)
                        let sessions = try decoder.decode([Session].self, from: data)
                        print("✅ History-Decodiert:", sessions)
                        groupSessions(sessions)
                    } catch {
                        print("🔴 History-Decode-Error:", error)
                    }

                case .failure(let err):
                    print("🔴 Fehler beim Laden der History:", err.localizedDescription)
                }
            }
        }
    }


    // Locations vom Backend
    private func fetchLocations() {
        guard let url = URL(string: "http://172.16.42.23:3000/web/allLocations") else { return }
        APIClient.shared.getJSON(url) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let json):
                    guard let arr = json as? [[String: Any]],
                          let data = try? JSONSerialization.data(withJSONObject: arr)
                    else { return }
                    availableLocations = (try? decoder.decode([AvailableLocation].self, from: data)) ?? []
                case .failure:
                    break
                }
            }
        }
    }

    // Gruppiert raw Sessions → MonthHistory
    private func groupSessions(_ sessions: [Session]) {
        // in SessionGroup umwandeln
        let sessionGroups = sessions.map { s in
            var events: [CheckEvent] = [
                .init(type: .checkIn,  date: s.startTime, building: s.locationName)
            ]
            if let out = s.endTime {
                events.append(.init(type: .checkOut, date: out, building: s.locationName))
            }
            events.sort { $0.date < $1.date }
            return SessionGroup(id: s.sessionID, events: events)
        }

        // nach Monat gruppieren
        let byMonth = Dictionary(grouping: sessionGroups) { group in
            let fmt = DateFormatter()
            fmt.locale = Locale(identifier: "de_DE")
            fmt.dateFormat = "LLLL yyyy"
            return fmt.string(from: group.events.first!.date).capitalized
        }
        historyByMonth = byMonth.map { key, groups in
            let sorted = groups.sorted {
                $0.events.first!.date > $1.events.first!.date
            }
            return MonthHistory(monthName: key, sessions: sorted)
        }
        .sorted { $0.monthName < $1.monthName }

        monthIndex = 0
    }
}

// MARK: – SessionCard
struct SessionCard: View {
    let group: SessionGroup

    var body: some View {
        VStack(spacing: 12) {
            if let first = group.events.first {
                Text("\(first.date, style: .date), \(first.building)")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity)
            }
            Divider()
            ForEach(group.events) { event in
                HStack(spacing: 12) {
                    Image(systemName: event.type.iconName)
                        .font(.title2)
                        .foregroundColor(event.type.color)
                    HStack(spacing: 4) {
                        Text(VerlaufView.timeFormatter.string(from: event.date))
                            .font(.headline)
                            .foregroundStyle(.black)
                        Text(event.type.rawValue)
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    Spacer()
                }
            }
            if group.events.first(where: { $0.type == .checkOut }) == nil {
                HStack(spacing: 12) {
                    Image(systemName: "clock.fill")
                        .font(.title2)
                        .foregroundColor(.orange)
                    Text("Noch anwesend")
                        .font(.headline)
                        .foregroundStyle(.black)
                    Spacer()
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: – EditSessionView (unverändert)
struct EditSessionView: View {
    @State private var showTimeError = false

    @State private var showDeleteConfirmation = false
    @Environment(\.dismiss) private var dismiss
    @Binding var sessionGroup: SessionGroup
    let locations: [AvailableLocation]
    @State private var startTime: Date
    @State private var endTime: Date?
    @State private var selectedLocation: String

    init(sessionGroup: Binding<SessionGroup>, locations: [AvailableLocation]) {
        self._sessionGroup = sessionGroup
        self.locations = locations
        let events = sessionGroup.wrappedValue.events
        _startTime = State(initialValue: events.first?.date ?? Date())
        _endTime   = State(initialValue: events.first(where: { $0.type == .checkOut })?.date)
        _selectedLocation = State(initialValue: events.first?.building ?? locations.first?.name ?? "")
    }

    var body: some View {
        Form {
            Section(header: Text("Datum & Zeit")) {
                DatePicker("Check-In", selection: $startTime,
                           displayedComponents: [.date, .hourAndMinute])
                DatePicker("Check-Out",
                           selection: Binding(get: { endTime ?? startTime },
                                              set: { endTime = $0 }),
                           displayedComponents: [.date, .hourAndMinute])
            }
            Section(header: Text("Standort ändern")) {
                Picker("Standort", selection: $selectedLocation) {
                  ForEach(locations) { loc in
                    Text(loc.name).tag(loc.name)
                  }
                }
                .pickerStyle(MenuPickerStyle())
            }
            Button("Löschen", role: .destructive) {
                showDeleteConfirmation = true
                            }
            .alert("Wirklich löschen?", isPresented: $showDeleteConfirmation) {
                Button ("ja", role: .destructive)
                {
                    SessionService.deleteSession(SessionID: sessionGroup.id) { result in
                        switch result {
                        case .success:
                            print(sessionGroup.id)
                            print("✅ geläöcht erfolgreich")
                            DispatchQueue.main.async {
                                dismiss()
                            }
                        case .failure(let err):
                            print("❌ nicht gelöscht-Fehler:", err)
                        }
                    }
      
                    
                
                    
                }
                Button("Nein", role: .cancel){}
            }
            Section {
                Button("Speichern") {
                    if let out = endTime, out < startTime {
                        showTimeError = true
                        return
                    }else{
                        showTimeError = false
                    }
                    let locationId = locations.first { $0.name == selectedLocation }!.id
                    SessionService.editSession(
                      sessionId: sessionGroup.id,
                      locationId: locationId,
                      checkIn: startTime,
                      checkOut: endTime
                    ) { result in
                      DispatchQueue.main.async {
                        switch result {
                        case .success:
                          // zurückkehren und UI updaten
                          dismiss()
                        case .failure(let error):
                          print("❌ EditSession-Error:", error)
                        }
                      }
                    }
//                    

                }
                .alert("Zeitfehler", isPresented: $showTimeError) {
                  Button("OK", role: .cancel) { }
                } message: {
                  Text("Die Check‑Out‑Zeit muss nach der Check‑In‑Zeit liegen.")
                }
            }
        }
        .navigationTitle("Session bearbeiten")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: – Preview
struct VerlaufView_Previews: PreviewProvider {
    static var previews: some View {
        VerlaufView()
    }
}
