import WidgetKit
import SwiftUI

private let appGroupIdentifier = "group.cn.blackbook.blackbook"
private let widgetPayloadKey = "today_widget_payload"

struct CourseItem: Decodable, Identifiable {
    var id: String { "\(name)-\(time)-\(place)" }
    let name: String
    let time: String
    let place: String
    let teacher: String
    let iconKey: String?
    let colorKey: String?
}

struct TodayPayload: Decodable {
    let title: String
    let subtitle: String
    let referenceTime: String
    let courses: [CourseItem]
}

struct TodayEntry: TimelineEntry {
    let date: Date
    let payload: TodayPayload
}

struct TodayClassesProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry {
        TodayEntry(
            date: Date(),
            payload: TodayPayload(
                title: "今日课程",
                subtitle: "2025-2026-2  第1周",
                referenceTime: "08:00",
                courses: [
                    CourseItem(
                        name: "化工原理",
                        time: "08:00-09:35",
                        place: "三教304",
                        teacher: "",
                        iconKey: "chemistry",
                        colorKey: "chemistry"
                    )
                ]
            )
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        completion(TodayEntry(date: Date(), payload: loadPayload()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        let entry = TodayEntry(date: Date(), payload: loadPayload())
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(300))))
    }

    private func loadPayload() -> TodayPayload {
        guard
            let defaults = UserDefaults(suiteName: appGroupIdentifier),
            let text = defaults.string(forKey: widgetPayloadKey),
            let data = text.data(using: .utf8),
            let payload = try? JSONDecoder().decode(TodayPayload.self, from: data)
        else {
            return TodayPayload(
                title: "今日课程",
                subtitle: "打开石大课表同步课程",
                referenceTime: "--:--",
                courses: []
            )
        }
        return payload
    }
}

struct TodayClassesWidget: Widget {
    let kind = "TodayClassesWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TodayClassesProvider()) { entry in
            TodayClassesWidgetView(entry: entry)
        }
        .configurationDisplayName("今日课程")
        .description("显示今天剩余课程")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct TodayClassesWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodayEntry

    private var courseLimit: Int {
        switch family {
        case .systemSmall:
            return 2
        case .systemMedium:
            return 3
        default:
            return 6
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(entry.payload.title)
                    .font(.system(size: family == .systemSmall ? 18 : 20, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(entry.payload.referenceTime)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Text(entry.payload.subtitle)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if entry.payload.courses.isEmpty {
                Spacer()
                Text("今天剩余时间没有课程")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                VStack(spacing: 6) {
                    ForEach(entry.payload.courses.prefix(courseLimit)) { course in
                        CourseRow(course: course, compact: family == .systemSmall)
                    }
                }
            }
        }
        .padding(family == .systemSmall ? 12 : 14)
        .background(Color(.systemBackground))
        .widgetURL(URL(string: "blackbook://today"))
    }
}

struct CourseRow: View {
    let course: CourseItem
    let compact: Bool

    private var accent: Color {
        switch course.colorKey ?? course.iconKey ?? "general" {
        case "chemistry", "experiment":
            return Color(red: 0.78, green: 0.46, blue: 0.09)
        case "math":
            return Color(red: 0.45, green: 0.35, blue: 0.78)
        case "computer":
            return Color(red: 0.09, green: 0.46, blue: 0.72)
        case "sports":
            return Color(red: 0.09, green: 0.49, blue: 0.66)
        case "thinking", "environment", "geology":
            return Color(red: 0.15, green: 0.50, blue: 0.35)
        default:
            return Color(red: 0.71, green: 0.12, blue: 0.14)
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(accent)
                .frame(width: 3)
                .clipShape(RoundedRectangle(cornerRadius: 1))
            Image(systemName: symbolName(for: course.iconKey))
                .font(.system(size: compact ? 14 : 16, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: compact ? 16 : 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(course.name)
                    .font(.system(size: compact ? 13 : 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text("\(course.time)  \(course.place)")
                    .font(.system(size: compact ? 10 : 11, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, compact ? 5 : 6)
        .padding(.horizontal, compact ? 6 : 8)
        .background(accent.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 2))
    }

    private func symbolName(for key: String?) -> String {
        switch key {
        case "computer":
            return "desktopcomputer"
        case "ai_data":
            return "chart.line.uptrend.xyaxis"
        case "math":
            return "function"
        case "physics":
            return "bolt"
        case "chemistry", "experiment":
            return "flask"
        case "practice":
            return "hammer"
        case "geology":
            return "mountain.2"
        case "engineering":
            return "building.2"
        case "mechanical":
            return "gearshape.2"
        case "materials":
            return "shippingbox"
        case "environment":
            return "leaf"
        case "economy":
            return "building.columns"
        case "law":
            return "scale.3d"
        case "language":
            return "character.book.closed"
        case "sports":
            return "basketball"
        case "thinking":
            return "brain.head.profile"
        case "design":
            return "paintbrush"
        case "article":
            return "doc.text"
        default:
            return "book.closed"
        }
    }
}
