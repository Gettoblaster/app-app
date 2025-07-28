import SwiftUI

// Demo-Modell für die Preview
struct SampleDayStat: Identifiable, Codable {
    let id = UUID()
    let day: String
    let hours: Double
    let location: String
}

// Backend-Modelle
struct Statistic: Decodable {
    let first_checkin: Date
    let last_checkout: Date?
    let current_status: String
    let days_with_logs_in_month: String
    let average_checkin_time: String?
    let weekly_summary: [WeekSummary]
}

struct WeekSummary: Decodable, Identifiable {
    var id: String { week }
    let week: String
    let days: [DayStat]
}

struct DayStat: Decodable, Identifiable {
    var id: UUID { UUID() }
    let day: String
    let locationId: Int
    let locationName: String
    let hours: Double
}

// Decoder für ISO-Dates
private let isoDecoder: JSONDecoder = {
    let d = JSONDecoder()
    let fmt = DateFormatter()
    fmt.locale = Locale(identifier: "en_US_POSIX")
    fmt.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
    d.dateDecodingStrategy = .formatted(fmt)
    return d
}()

enum CheckInStatus: String, Codable {
    case present, away
}

// Beispiel-Daten für die Preview
struct SampleWeeklyStatsEntry: Codable {
    let checkInTime: String?
    let lastCheckOut: String?
    let checkInStatus: CheckInStatus?
    let officeDaysThisMonth: Int?
    let avgCheckInTime: String?
    let weeklyStats: [SampleDayStat]
}

func loadStats(from filename: String) -> [SampleWeeklyStatsEntry] {
    guard let url = Bundle.main.url(forResource: filename, withExtension: "json"),
          let data = try? Data(contentsOf: url) else {
        print("nicht gefunden")
        return []
    }
    let decoder = JSONDecoder()
    return (try? decoder.decode([SampleWeeklyStatsEntry].self, from: data)) ?? []
}

struct AttendanceView: View {
    let userId: Int

    @State private var stats: [Statistic] = []
    @State private var isLoading = true
    @State private var selectedWeekIndex = 0

    private let chartHeight: CGFloat = 150

    private var first: Statistic? { stats.first }

    private var weeks: [[DayStat]] {
        first?.weekly_summary.map { $0.days } ?? []
    }

    private var checkInTime: String {
        guard let date = first?.first_checkin else { return "" }
        return timeFormatter.string(from: date)
    }

    private var lastCheckOut: String {
        guard let date = first?.last_checkout else { return "" }
        return timeFormatter.string(from: date)
    }

    private var checkInStatus: CheckInStatus {
        first?.current_status.lowercased() == "anwesend" ? .present : .away
    }

    private var officeDaysThisMonth: Int {
        Int(first?.days_with_logs_in_month ?? "0") ?? 0
    }

    private var avgCheckInTime: String {
        first?.average_checkin_time ?? "--"
    }

    private var buildingColors: [String: Color] {
        var palette: [Color] = [.red, .blue, .green, .orange, .pink, .purple, .yellow, .gray]
        palette.shuffle()
        let locations = Set(weeks.flatMap { $0.map { $0.locationName } })
        var dict = [String: Color]()
        for (i, loc) in locations.enumerated() {
            dict[loc] = palette.indices.contains(i) ? palette[i] : Color(
                red: .random(in: 0...1),
                green: .random(in: 0...1),
                blue: .random(in: 0...1)
            )
        }
        return dict
    }

    private var maxHours: Double {
        let week = weeks[safe: selectedWeekIndex] ?? []
        return max(1, week.map { $0.hours }.max() ?? 1)
    }

    private func formatHours(_ h: Double) -> String {
        if h.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f h", h)
        } else {
            return String(format: "%.1f h", h)
        }
    }

    private var durationString: String {
        let interval: TimeInterval =
            (checkInStatus == .present
             ? Date().timeIntervalSince(parseTime(checkInTime) ?? Date())
             : (parseTime(lastCheckOut) ?? Date())
                .timeIntervalSince(parseTime(checkInTime) ?? Date()))
        let hours = Int(interval) / 3600
        let mins = (Int(interval) % 3600) / 60
        return "\(hours)h \(mins)min"
    }

    private func parseTime(_ str: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        guard let t = formatter.date(from: str) else { return nil }
        let today = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        let timeCmp = Calendar.current.dateComponents([.hour, .minute], from: t)
        return Calendar.current.date(from: DateComponents(
            year: today.year, month: today.month, day: today.day,
            hour: timeCmp.hour, minute: timeCmp.minute
        ))
    }

    private let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 4) {
                Text("Du hast dich um \(checkInTime) eingecheckt")
                    .font(.footnote).foregroundColor(.gray)
                (
                    Text(checkInStatus == .present ? "Du bist heute seit " : "Du warst heute ") +
                    Text(durationString).fontWeight(.semibold) +
                    Text(" anwesend")
                )
                .font(.title3)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(buildingColors.keys.sorted(), id: \String.self) { key in
                        HStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(buildingColors[key]!)
                                .frame(width: 16, height: 16)
                            Text(key).font(.caption)
                        }
                    }
                }
                .padding(.horizontal)
            }

            TabView(selection: $selectedWeekIndex) {
                ForEach(weeks.indices, id: \.self) { idx in
                    HStack(alignment: .bottom, spacing: 16) {
                        ForEach(weeks[idx]) { stat in
                            VStack(spacing: 6) {
                                Text(formatHours(stat.hours))
                                    .font(.caption2).foregroundColor(.gray)
                                Rectangle()
                                    .fill(buildingColors[stat.locationName] ?? .gray)
                                    .frame(width: 20,
                                           height: CGFloat(stat.hours / maxHours) * chartHeight)
                                Text(stat.day).font(.caption).foregroundColor(.gray)
                            }
                        }
                    }
                    .frame(height: chartHeight + 30)
                    .padding(.horizontal)
                    .tag(idx)
                }
            }
            .frame(height: chartHeight + 50)
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))

            HStack(spacing: 16) {
                StatBox(title: "In Office Tage", value: "\(officeDaysThisMonth)")
                StatBox(title: "Ø Check-in-Zeit", value: avgCheckInTime)
            }
            Spacer()
        }
        .task { fetchStats() }
        .padding(.top, 30)
        .navigationTitle("Anwesenheit")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(hex: "FEFEFE"))
    }

    private func fetchStats() {
        SessionService.fetchStatistics(userId: userId) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let fetched):
                    self.stats = fetched
                case .failure(let err):
                    print("❌ Stats‑Fehler:", err)
                    self.stats = []
                }
                self.isLoading = false
            }
        }
    }
}

private struct StatBox: View {
    let title, value: String
    var body: some View {
        VStack(spacing: 6) {
            Text(title).font(.subheadline).foregroundColor(.gray)
            Text(value).font(.title2).fontWeight(.semibold)
        }
        .padding().background(Color.white)
        .cornerRadius(12).shadow(radius: 4)
    }
}

extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

struct AttendanceView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            AttendanceView(userId: 1)
        }
    }
}
