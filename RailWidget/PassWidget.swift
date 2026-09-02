import WidgetKit
import SwiftUI
import SwiftData
import os

// MARK: - simple entry
struct SimpleEntry: TimelineEntry {
    let date: Date
    let passName: String?
    let expiry_date: Date?
    let image: Data?
}

// MARK: - provider
struct Provider: TimelineProvider {
    typealias Entry = SimpleEntry

    private static let logger = Logger(subsystem: "com.francescoparadis.Rail", category: "PassWidget")

    @MainActor
    func fetchFirstPass() -> (String?, Date?, Data?) {
        do {
            let container = try SharedSwiftData.makeReadOnlyContainer()
            let descriptor = FetchDescriptor<Pass>(sortBy: [SortDescriptor(\.expiry_date)])
            let passes = try container.mainContext.fetch(descriptor)
            
            if let principalPass = passes.first(where: { $0.is_principal }) {
                return (principalPass.name, principalPass.expiry_date, principalPass.image)
            }
        } catch {
            Self.logger.error("Failed to load pass widget data: \(error.localizedDescription, privacy: .public)")
        }
        return (nil, nil, nil)
    }

    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(
            date: Date(),
            passName: "Settimanale",
            expiry_date: Calendar.current.date(byAdding: .day, value: 7, to: Date()),
            image: nil
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> ()) {
        Task {
            let (name, expiry_date, image) = await fetchFirstPass()
            let entry = SimpleEntry(
                date: Date(),
                passName: name,
                expiry_date: expiry_date,
                image: image
            )
            completion(entry)
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleEntry>) -> ()) {
        Task {
            let (name, expiry_date, image) = await fetchFirstPass()
            let entry = SimpleEntry(
                date: Date(),
                passName: name,
                expiry_date: expiry_date,
                image: image
            )
            let timeline = Timeline(entries: [entry], policy: .atEnd)
            completion(timeline)
        }
    }
}

// MARK: - widget view
struct PassWidgetEntryView : View {
    // MARK: - Properties

    var entry: Provider.Entry

    // MARK: - Body

    var body: some View {
        Group {
            if let passName = entry.passName, let expiry_date = entry.expiry_date {
                mediumLayout(name: passName, date: expiry_date)
            } else {
                ContentUnavailableView("No pass selected", systemImage: "ticket.fill")
                    .fontDesign(widgetFontDesign)
            }
        }
        .containerBackground(.ultraThinMaterial, for: .widget)
        .widgetURL(URL(string: "railapp://view-pass"))
    }

    // MARK: - Subviews

    func mediumLayout(name: String, date: Date) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                headerView
                
                Text(name)
                    .font(.title2).fontWeight(.semibold).fontDesign(widgetFontDesign)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                
                Spacer()
                
                expiryDateView(for: date)
            }
            
            Spacer(minLength: 0)
            
            codeImageView
        }
    }

    private var headerView: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "ticket.fill")
                Text("Pass")
            }
            .font(.footnote).fontWeight(.medium).fontDesign(widgetFontDesign)
            .foregroundStyle(.secondary)
                
            Divider()
        }
    }

    @ViewBuilder
    private func expiryDateView(for date: Date) -> some View {
        let isActive = date >= Date()
        let color: Color = isActive ? .green : .red
        let text = isActive ? "Active" : "Expired"
        
        VStack(alignment: .leading, spacing: 4) {
            Text(text)
                .font(.footnote).fontWeight(.bold).fontDesign(widgetFontDesign)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .foregroundStyle(.white)
                .background(color)
                .clipShape(Capsule())
            
            Group {
                if !isActive {
                    Text("Expired on \(date.formatted(.dateTime.day().month().year()))")
                } else {
                    let totalDays = Calendar.current.dateComponents([.day], from: Date(), to: date).day ?? 0
                    if totalDays == 0 {
                        Text("Expires today")
                    } else if totalDays == 1 {
                        Text("Expires tomorrow")
                    } else {
                        Text("Expires in \(totalDays) days")
                    }
                }
            }
            .font(.caption).fontWeight(.medium).fontDesign(widgetFontDesign)
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.leading, 4)
        }
    }

    @ViewBuilder
    private var codeImageView: some View {
        if let imageData = entry.image, let uiImage = UIImage(data: imageData) {
            Image(uiImage: uiImage)
                .resizable()
                .interpolation(.none)
                .scaledToFit()
                .padding(6)
                .background(Color.white)
                .cornerRadius(12)
                .frame(maxHeight: .infinity)
        } else {
            VStack {
                Image(systemName: "qrcode.viewfinder")
                    .font(.title)
                Text("No Code")
                    .font(.caption2)
            }
            .foregroundStyle(.secondary)
            .fontDesign(widgetFontDesign)
            .frame(width: 80)
        }
    }
}

// MARK: - widget
struct PassWidget: Widget {
    let kind: String = "PassWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            PassWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Pass Widget")
        .description("Displays your principal pass QR code.")
        .supportedFamilies([.systemMedium])
    }
}

// MARK: - previews
#Preview("Medium", as: .systemMedium) {
    PassWidget()
} timeline: {
    SimpleEntry(
        date: .now,
        passName: "Mensile",
        expiry_date: Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? .now,
        image: scaleImage(data: UIImage(named: "sample_code")?.pngData(), to: 400)
    )
    SimpleEntry(
        date: .now,
        passName: "Settimanale",
        expiry_date: Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? .now,
        image: scaleImage(data: UIImage(named: "sample_code")?.pngData(), to: 400)
    )
}

#Preview("Unavailable", as: .systemMedium) {
    PassWidget()
} timeline: {
    SimpleEntry(
        date: .now,
        passName: nil,
        expiry_date: nil,
        image: nil
    )
}
