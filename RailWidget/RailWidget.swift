import WidgetKit
import SwiftUI
import SwiftData

// widget shared variables
let widgetFontDesign: Font.Design = .rounded

// MARK: - simple entry
struct SimpleEntry: TimelineEntry {
    let date: Date
    
    let pass_name: String?
    let expiry_date: Date?
    let image: Data?
}

// MARK: - provider
struct Provider: TimelineProvider {
    typealias Entry = SimpleEntry

    // get first principal pass from shared SwiftData container
    @MainActor
    func fetchFirstPass() -> (String?, Date?, Data?) {
        do {
            /// group identifier
            let groupIdentifier = "group.com.francescoparadis.Rail"
            
            /// shared container URL
            guard let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier) else {
                return (nil, nil, nil)
            }
            let databaseURL = groupURL.appendingPathComponent("default.store")
            
            /// configuration for SwiftData
            let schema = Schema([
                Train.self,
                Stop.self,
                Seat.self,
                Favorite.self,
                Pass.self
            ])
            
            let config = ModelConfiguration(
                groupIdentifier,
                schema: schema,
                url: databaseURL,
                allowsSave: false
            )
            let container = try ModelContainer(for: schema, configurations: config)
            
            let descriptor = FetchDescriptor<Pass>(sortBy: [SortDescriptor(\.expiry_date)])
            let passes = try container.mainContext.fetch(descriptor)
            
            /// get the first principal pass
            if let principal_pass = passes.first(where: { $0.is_principal }) {
                return (principal_pass.name, principal_pass.expiry_date, principal_pass.image)
            }
        } catch {
            print("Errore SwiftData Widget: \(error)")
        }
        return (nil, nil, nil)
    }

    // define placeholder (needed for widget gallery)
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(
            date: Date(),
            pass_name: "Settimanale",
            expiry_date: Calendar.current.date(byAdding: .day, value: 7, to: Date()),
            image: nil
        )
    }

    // define snapshot (needed for widget gallery)
    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> ()) {
        Task {
            let (name, expiry_date, image) = await fetchFirstPass()
            let entry = SimpleEntry(
                date: Date(),
                pass_name: name,
                expiry_date: expiry_date,
                image: image
            )
            completion(entry)
        }
    }

    // define timeline (needed for widget updates)
    func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleEntry>) -> ()) {
        Task {
            let (name, expiry_date, image) = await fetchFirstPass()
            let entry = SimpleEntry(
                date: Date(),
                pass_name: name,
                expiry_date: expiry_date,
                image: image
            )
            let timeline = Timeline(entries: [entry], policy: .atEnd)
            completion(timeline)
        }
    }
}

// MARK: - widget view
struct RailWidgetEntryView : View {
    // MARK: - variables
    // environment variables
    @Environment(\.widgetFamily) var family
    
    // pass variables
    var entry: Provider.Entry
        
    var body: some View {
        Group {
            if let pass_name = entry.pass_name, let expiry_date = entry.expiry_date {
                switch family {
                case .systemSmall:
                    smallLayout(name: pass_name, date: expiry_date)
                case .systemMedium:
                    mediumLayout(name: pass_name, date: expiry_date)
                default:
                    largeLayout(name: pass_name, date: expiry_date)
                }
            } else {
                ContentUnavailableView("No pass selected", systemImage: "ticket.fill")
                    .fontDesign(widgetFontDesign)
                    .lineLimit(1).truncationMode(.tail)
                    .minimumScaleFactor(0.5)
            }
        }
        .containerBackground(.ultraThinMaterial, for: .widget)
        .widgetURL(URL(string: "railapp://view-pass"))
    }
    
    // MARK: - layouts
    @ViewBuilder
    func smallLayout(name: String, date: Date) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            headerView()
            
            nameView(for: name)
            
            Spacer()
            
            expiryDateView(for: date)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    func mediumLayout(name: String, date: Date) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                headerView()
                
                nameView(for: name)
                
                Spacer()
                
                expiryDateView(for: date)
            }
            
            Spacer()
            
            codeImageView()
        }
    }
    
    @ViewBuilder
    func largeLayout(name: String, date: Date) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            headerView()
            
            nameView(for: name)
            
            expiryDateView(for: date)
            
            Spacer(minLength: 8)
            
            codeImageView()
        }
    }
    
    // MARK: - reusable views
    @ViewBuilder
    private func headerView() -> some View {
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
    private func nameView(for name: String) -> some View {
        Text(name)
            .font(.title).fontWeight(.semibold).fontDesign(widgetFontDesign)
            .lineLimit(1).truncationMode(.tail)
            .minimumScaleFactor(0.5)
    }
    
    @ViewBuilder
    private func expiryDateView(for date: Date) -> some View {
        let isActive = date >= Date()
        let color: Color = isActive ? .green : .red
        let text = isActive ? "Active" : "Expired"
        let time_remaining: String = {
            if date < Date() {
                let dateString = date.formatted(.dateTime.day().month().year())
                return String(localized: "Expired on \(dateString)")
            }
            
            let totalDays = Calendar.current.dateComponents([.day], from: Date(), to: date).day ?? 0
            if totalDays == 0 { return String(localized: "Expires today") }
            if totalDays == 1 { return String(localized: "Expires tomorrow") }
            
            return String(localized: "Expires in \(totalDays) days")
        }()
        
        switch family {
        case .systemSmall:
            Text(text)
                .font(.footnote).fontWeight(.semibold).fontDesign(widgetFontDesign)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .foregroundStyle(color)
                .background(color.opacity(0.15))
                .clipShape(Capsule())
            
        default:
            HStack {
                Text(text)
                    .font(.footnote).fontWeight(.semibold).fontDesign(widgetFontDesign)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .foregroundStyle(color)
                    .background(color.opacity(0.15))
                    .clipShape(Capsule())
                
                Text(time_remaining)
                    .font(.footnote).fontWeight(.medium).fontDesign(widgetFontDesign)
                    .foregroundStyle(color)
                    .lineLimit(1).truncationMode(.tail)
                    .minimumScaleFactor(0.5)
            }
        }
    }
    
    @ViewBuilder
    private func codeImageView() -> some View {
        if let imageData = entry.image, let uiImage = UIImage(data: imageData) {
            Image(uiImage: uiImage)
                .resizable()
                .interpolation(.none)
                .scaledToFit()
                .padding(family == .systemLarge ? 16 : 8)
                .background(Color.white)
                .cornerRadius(16)
        } else {
            ContentUnavailableView {
                Label("No Code", systemImage: "qrcode.viewfinder")
            }
            .scaleEffect(0.8)
        }
    }
}

// MARK: - widget
@main
struct RailWidget: Widget {
    let kind: String = "RailWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            RailWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Rail Widget")
    }
}

// MARK: - previews
#Preview("Small", as: .systemSmall) {
    RailWidget()
} timeline: {
    SimpleEntry(
        date: .now,
        pass_name: "Settimanale",
        expiry_date: .now.addingTimeInterval(86400),
        image: UIImage(named: "sample_code")?.pngData()
    )
}

#Preview("Medium", as: .systemMedium) {
    RailWidget()
} timeline: {
    SimpleEntry(
        date: .now,
        pass_name: "Mensile",
        expiry_date: .now.addingTimeInterval(86400 * 91),
        image: UIImage(named: "sample_code")?.pngData()
    )
}

#Preview("Large", as: .systemLarge) {
    RailWidget()
} timeline: {
    SimpleEntry(
        date: .now,
        pass_name: "Annuale",
        expiry_date: .now.addingTimeInterval(-86400 * 91),
        image: UIImage(named: "sample_code")?.pngData()
    )
}

#Preview("Unavailable - Small", as: .systemSmall) {
    RailWidget()
} timeline: {
    SimpleEntry(
        date: .now,
        pass_name: nil,
        expiry_date: nil,
        image: nil
    )
}

#Preview("Unavailable - Medium", as: .systemMedium) {
    RailWidget()
} timeline: {
    SimpleEntry(
        date: .now,
        pass_name: nil,
        expiry_date: nil,
        image: nil
    )
}

#Preview("Unavailable - Large", as: .systemLarge) {
    RailWidget()
} timeline: {
    SimpleEntry(
        date: .now,
        pass_name: nil,
        expiry_date: nil,
        image: nil
    )
}
