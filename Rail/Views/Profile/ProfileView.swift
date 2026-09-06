import SwiftUI
import SwiftData
import PhotosUI

struct ProfileView: View {
    // MARK: - Properties

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.locale) private var locale
    @Query private var profiles: [UserProfile]
    @State private var showImagePicker = false
    @State private var profileImage: UIImage?
    @State private var profileAccentColor: Color = .gray
    @State private var profilePhotoFrame: CGRect = .zero
    @State private var formattedDelay = "—"
    @State private var formattedDistance = "—"
    @State private var formattedTrains = "—"
    @State private var formattedCancelled = "—"
    @State private var formattedPasses = "—"
    @State private var formattedPassSpend = "—"

    // MARK: - Computed

    private var profile: UserProfile? { profiles.primary }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if let profile {
                    profileForm(for: profile)
                } else {
                    ProgressView()
                }
            }
            .fontDesign(.rounded)
            .coordinateSpace(name: "profileRoot")
            .background {
                if profileImage != nil, !profilePhotoFrame.isEmpty {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    profileAccentColor.opacity(0.6),
                                    profileAccentColor.opacity(0.32),
                                    profileAccentColor.opacity(0.12),
                                    profileAccentColor.opacity(0)
                                ],
                                center: .center,
                                startRadius: 40,
                                endRadius: 200
                            )
                        )
                        .frame(width: 440, height: 440)
                        .position(x: profilePhotoFrame.midX, y: profilePhotoFrame.midY)
                        .allowsHitTesting(false)
                }
            }
            .onPreferenceChange(ProfilePhotoFrameKey.self) { profilePhotoFrame = $0 }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
            }
        }
        .background {
            ZStack {
                // The rows on this screen are secondarySystemGroupedBackground, which
                // in dark mode is the same colour as the app's usual backdrop — the
                // settings list vanished into it. This is the ground that colour is
                // meant to sit on: lighter than the rows in light mode, darker in dark.
                Color(.systemGroupedBackground)
                ProfileBlueprintPattern()
            }
            .ignoresSafeArea()
        }
        .task(id: profile?.photo) {
            let photoData = profile?.photo
            if let photoData {
                let image = await Task.detached(priority: .utility) {
                    UIImage(data: photoData)
                }.value
                profileImage = image
                if let image {
                    profileAccentColor = await Task.detached(priority: .utility) {
                        Color(image.dominantColor() ?? .gray)
                    }.value
                } else {
                    profileAccentColor = .gray
                }
            } else {
                profileImage = nil
                profileAccentColor = .gray
            }
            await loadStats()
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private func profileForm(for profile: UserProfile) -> some View {
        @Bindable var profile = profile

        Form {
            Section {
                VStack(spacing: 8) {
                    Button {
                        showImagePicker = true
                    } label: {
                        if let profileImage {
                            Image(uiImage: profileImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 160, height: 160)
                                .clipShape(Circle())
                                .shadow(color: profileAccentColor.opacity(0.35), radius: 12, y: 4)
                        } else {
                            Circle()
                                .fill(Color(UIColor.secondarySystemGroupedBackground))
                                .frame(width: 160, height: 160)
                                .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
                                .overlay(
                                    Image(systemName: "camera.fill")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 60, height: 60)
                                        .foregroundColor(.gray)
                                )
                        }
                    }
                    .background {
                        GeometryReader { geo in
                            Color.clear.preference(
                                key: ProfilePhotoFrameKey.self,
                                value: geo.frame(in: .named("profileRoot"))
                            )
                        }
                    }
                    .sheet(isPresented: $showImagePicker) {
                        ImagePicker(imageData: Binding(
                            get: { profile.photo },
                            set: { profile.photo = $0 }
                        ))
                    }

                    TextField("Name", text: $profile.name)
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.primary)
                        .textFieldStyle(.plain)
                        .padding(.top, 4)
                }
            }
            .listRowBackground(Color.clear)

            Section(header: Text("Trains")) {
                VStack(spacing: 16) {
                    HStack(spacing: 16) {
                        statCard(
                            title: "Trains",
                            value: formattedTrains,
                            systemImage: "train.side.front.car",
                            color: .blue
                        )

                        statCard(
                            title: "Distance",
                            value: formattedDistance,
                            systemImage: "map",
                            color: .blue
                        )
                    }

                    HStack(spacing: 16) {
                        statCard(
                            title: "Cancelled",
                            value: formattedCancelled,
                            systemImage: "xmark.circle.fill",
                            color: .red
                        )

                        statCard(
                            title: "Delay",
                            value: formattedDelay,
                            systemImage: "clock.badge.exclamationmark",
                            color: .red
                        )
                    }
                }
                .padding(.horizontal, -16)
            }
            .listRowBackground(Color.clear)

            Section(header: Text("Passes")) {
                HStack(spacing: 16) {
                    statCard(
                        title: "Passes",
                        value: formattedPasses,
                        systemImage: "ticket",
                        color: .green
                    )

                    statCard(
                        title: "Spent",
                        value: formattedPassSpend,
                        systemImage: "eurosign.circle",
                        color: .green
                    )
                }
                .padding(.horizontal, -16)
            }
            .listRowBackground(Color.clear)

            Section(header: Text("Settings")) {
                NavigationLink {
                    CalendarSettingsView(profile: profile)
                } label: {
                    Label("Calendar", systemImage: "calendar")
                        .labelReservedIconWidth(24)
                }

                NavigationLink {
                    EmailSettingsView(profile: profile)
                } label: {
                    Label("Email", systemImage: "envelope")
                        .labelReservedIconWidth(24)
                }

                NavigationLink {
                    NotificationSettingsView(profile: profile)
                } label: {
                    Label("Notifications", systemImage: "bell")
                        .labelReservedIconWidth(24)
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    // `title` takes a key, not a resolved string: `Text(String)` is the verbatim
    // overload, so these six cards stayed English under an Italian environment
    // while every Text(LocalizedStringKey) label around them followed it.
    private func statCard(title: LocalizedStringKey, value: String, systemImage: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: systemImage)
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }

            Text(value)
                .font(.title)
                .fontWeight(.bold)
                .contentTransition(.numericText())
        }
        .foregroundColor(color)
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(UIColor.secondarySystemGroupedBackground))
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(color.opacity(0.16))
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    // MARK: - Actions

    @MainActor
    private func loadStats() async {
        let container = modelContext.container
        let stats = await Task.detached(priority: .userInitiated) {
            let context = ModelContext(container)
            let trains = (try? context.fetch(FetchDescriptor<Train>())) ?? []
            let stops = (try? context.fetch(FetchDescriptor<Stop>())) ?? []

            // Every card counts the same journeys: the ones already travelled. Read
            // off different populations they cannot be reconciled — which is how the
            // card could report no trains and a distance at the same time.
            let pastItems = await TrainListBuilder.pastItems(trains: trains, stops: stops)

            let pastTrainsCount = pastItems.count
            let cancelledTrainsCount = pastItems.filter { $0.train.issue == "Treno cancellato" }.count

            let totalDelay = pastItems.reduce(0) { total, item in
                total + max(0, item.summary.last.arr_delay)
            }

            // The stops actually served, so a journey cut short is credited with the
            // distance it covered rather than the one it was sold for.
            var totalDistance = 0
            for item in pastItems where item.train.issue != "Treno cancellato" {
                let first = item.summary.firstNoIssues
                let last = item.summary.lastNoIssues
                guard first.name != last.name else { continue }
                totalDistance += distanceBetweenStations(from: first.name, to: last.name) ?? 0
            }

            let passes = (try? context.fetch(FetchDescriptor<Pass>())) ?? []
            // Passes without a recorded price simply don't add to the total.
            let passSpend = passes.compactMap(\.priceValue).reduce(0, +)

            return (pastTrainsCount, cancelledTrainsCount, totalDelay, totalDistance,
                    passes.count, passSpend)
        }.value

        formattedTrains = "\(stats.0)"
        formattedCancelled = "\(stats.1)"
        formattedDelay = formatDelay(stats.2)
        formattedDistance = formatDistance(stats.3)
        formattedPasses = "\(stats.4)"
        formattedPassSpend = formatCurrency(stats.5)
    }

    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        // Bare NumberFormatter reads the system locale on its own, same as
        // DateFormatter — it needs to be told which locale the view is in.
        formatter.locale = locale
        formatter.numberStyle = .currency
        formatter.currencyCode = "EUR"
        formatter.maximumFractionDigits = amount < 1000 ? 2 : 0
        return formatter.string(from: NSNumber(value: amount))
            ?? String(format: "%.2f \u{20AC}", amount)
    }

    private func formatDelay(_ delay: Int) -> String {
        if delay >= 60 {
            let hours = delay / 60
            let mins = delay % 60
            if mins == 0 { return "\(hours)h" }
            return "\(hours)h \(mins)m"
        }
        return "\(delay)m"
    }

    private func formatDistance(_ distance: Int) -> String {
        if distance >= 1000 {
            let thousands = Double(distance) / 1000.0
            return String(format: "%.1fk km", thousands).replacingOccurrences(of: ".0k", with: "k")
        }
        return "\(distance) km"
    }
}

private struct ProfilePhotoFrameKey: PreferenceKey {
    static let defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

private struct ProfileBlueprintPattern: View {
    // MARK: - Properties

    private let cellSize: CGFloat = 56
    private let iconSize: CGFloat = 24

    private let symbols: [String] = [
        "train.side.front.car",
        "tram",
        "bus",
        "airplane",
        "ferry",
        "bicycle",
        "car",
        "figure.walk",
        "map",
        "location",
        "ticket",
        "suitcase.rolling",
        "building.2",
        "globe.europe.africa",
        "mountain.2",
        "binoculars",
        "fuelpump",
        "road.lanes"
    ]

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            let columns = Int(ceil(geo.size.width / cellSize)) + 2
            let rows = Int(ceil(geo.size.height / cellSize)) + 2

            VStack(spacing: 0) {
                ForEach(0..<rows, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<columns, id: \.self) { column in
                            let index = (row * 3 + column * 5) % symbols.count
                            Image(systemName: symbols[index])
                                .font(.system(size: iconSize, weight: .semibold))
                                .symbolRenderingMode(.monochrome)
                                .foregroundStyle(Color.primary.opacity(0.05))
                                .frame(width: cellSize, height: cellSize)
                        }
                    }
                    .offset(x: row.isMultiple(of: 2) ? 0 : cellSize / 2)
                }
            }
            .offset(x: -cellSize / 2, y: -cellSize / 2)
        }
        .clipped()
        .allowsHitTesting(false)
    }
}

private nonisolated extension UIImage {
    /// Average color of the image, used as a soft accent glow behind the profile photo.
    func dominantColor() -> UIColor? {
        guard let inputImage = CIImage(image: self) else { return nil }
        guard let filter = CIFilter(
            name: "CIAreaAverage",
            parameters: [
                kCIInputImageKey: inputImage,
                kCIInputExtentKey: CIVector(cgRect: inputImage.extent)
            ]
        ),
        let outputImage = filter.outputImage else { return nil }

        var bitmap = [UInt8](repeating: 0, count: 4)
        let context = CIContext(options: [.workingColorSpace: NSNull()])
        context.render(
            outputImage,
            toBitmap: &bitmap,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )

        return UIColor(
            red: CGFloat(bitmap[0]) / 255,
            green: CGFloat(bitmap[1]) / 255,
            blue: CGFloat(bitmap[2]) / 255,
            alpha: 1
        )
    }
}

#Preview("Profile View") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Train.self, Stop.self, Seat.self, Favorite.self, Pass.self, UserProfile.self, configurations: config)

    let trainID = UUID()
    let train = Train(id: trainID, logo: "trenitalia", number: "9808", identifier: "9808-date", provider: "Trenitalia", last_update_time: Date(), delay: 0, direction: "Milano", issue: "")

    let stop1 = Stop(id: trainID, name: "Roma Termini", platform: "1", weather: "Sunny", is_selected: true, status: 0, is_completed: true, is_in_station: false, dep_delay: 0, arr_delay: 0, dep_time_id: Date().addingTimeInterval(-10000), arr_time_id: Date().addingTimeInterval(-10000), dep_time_eff: Date().addingTimeInterval(-10000), arr_time_eff: Date().addingTimeInterval(-10000), ref_time: Date())

    let stop2 = Stop(id: trainID, name: "Milano Centrale", platform: "2", weather: "Cloudy", is_selected: true, status: 0, is_completed: true, is_in_station: false, dep_delay: 10, arr_delay: 10, dep_time_id: Date().addingTimeInterval(600), arr_time_id: Date().addingTimeInterval(600), dep_time_eff: Date().addingTimeInterval(1200), arr_time_eff: Date().addingTimeInterval(1200), ref_time: Date())

    container.mainContext.insert(train)
    container.mainContext.insert(stop1)
    container.mainContext.insert(stop2)
    container.mainContext.insert(UserProfile(name: "Francesco"))

    return ContentView()
        .sheet(isPresented: .constant(true)) {
            ProfileView()
                .modelContainer(container)
        }
}
