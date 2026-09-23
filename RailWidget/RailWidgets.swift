import WidgetKit
import SwiftUI
import SwiftData
import os

// The home screen widget — the principal pass — and the bundle that registers it
// alongside the Live Activity, with its previews at the bottom. The Live Activity
// itself is in `TrainLiveActivity.swift`.

// MARK: - Bundle

@main
struct RailWidgets: WidgetBundle {
    var body: some Widget {
        PassWidget()
        TrainLiveActivity()
    }
}

// MARK: - Shared

/// The rounded face the whole app is set in, shared by every widget and the Live Activity.
let widgetFontDesign: Font.Design = .rounded

func scaleImage(data: Data?, to maxWidth: CGFloat) -> Data? {
    guard let data = data, let uiImage = UIImage(data: data) else { return nil }
    
    let currentSize = uiImage.size
    guard currentSize.width > maxWidth else { return data }
    
    let scale = maxWidth / currentSize.width
    let newHeight = currentSize.height * scale
    let newSize = CGSize(width: maxWidth, height: newHeight)
    
    UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
    uiImage.draw(in: CGRect(origin: .zero, size: newSize))
    let scaledImage = UIGraphicsGetImageFromCurrentImageContext()
    UIGraphicsEndImageContext()
    
    return scaledImage?.pngData()
}

// MARK: - Pass Entry
struct PassEntry: TimelineEntry {
    let date: Date
    let passName: String?
    let expiry_date: Date?
    let image: Data?
}

// MARK: - Pass Provider
struct PassProvider: TimelineProvider {
    typealias Entry = PassEntry

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

    func placeholder(in context: Context) -> PassEntry {
        PassEntry(
            date: Date(),
            passName: "Settimanale",
            expiry_date: Calendar.current.date(byAdding: .day, value: 7, to: Date()),
            image: nil
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (PassEntry) -> ()) {
        Task {
            let (name, expiry_date, image) = await fetchFirstPass()
            let entry = PassEntry(
                date: Date(),
                passName: name,
                expiry_date: expiry_date,
                image: image
            )
            completion(entry)
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PassEntry>) -> ()) {
        Task {
            let (name, expiry_date, image) = await fetchFirstPass()
            let entry = PassEntry(
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

// MARK: - Pass Widget View
struct PassWidgetEntryView : View {
    // MARK: - Properties

    var entry: PassProvider.Entry

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

// MARK: - Pass Widget Definition
struct PassWidget: Widget {
    let kind: String = "PassWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PassProvider()) { entry in
            PassWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Pass Widget")
        .description("Displays your principal pass QR code.")
        .supportedFamilies([.systemMedium])
    }
}

// MARK: - Previews

#Preview("Pass", as: .systemMedium) {
    PassWidget()
} timeline: {
    PassEntry(
        date: .now,
        passName: "Mensile",
        expiry_date: Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? .now,
        image: scaleImage(data: UIImage(named: "sample_code")?.pngData(), to: 400)
    )
    PassEntry(
        date: .now,
        passName: "Settimanale",
        expiry_date: Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? .now,
        image: scaleImage(data: UIImage(named: "sample_code")?.pngData(), to: 400)
    )
}

#Preview("Pass · none", as: .systemMedium) {
    PassWidget()
} timeline: {
    PassEntry(
        date: .now,
        passName: nil,
        expiry_date: nil,
        image: nil
    )
}
