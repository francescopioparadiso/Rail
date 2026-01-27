import SwiftUI
import SwiftData

struct AddFavoriteView: View {
    // MARK: - variables
    // environment variables
    @Environment(\.dismiss) private var dismiss
    
    // database variables
    @Environment(\.modelContext) private var modelContext
    @Query private var favorites: [Favorite]
    
    private var favorites_sorted: [Favorite] {
        return favorites.sorted { first, second in
            let firstValid = !(favorites_fetched[first.id]?.isEmpty ?? true)
            let secondValid = !(favorites_fetched[second.id]?.isEmpty ?? true)
            
            if firstValid != secondValid {
                return firstValid && !secondValid
            }
            
            return first.index < second.index
        }
    }
    
    // favorite variables
    @Binding var favorites_fetched: [UUID: [String: Any]]
    @Binding var favoriteID_selected: UUID?
    
    // MARK: - main view
    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                // MARK: - favorites list
                if favorites.isEmpty {
                    ContentUnavailableView("No favorites added",
                                           systemImage: "heart.slash.fill",
                                           description: Text("Add a new favorites using the button in the train view."))
                    .foregroundColor(Color.secondary)
                    .fontDesign(app_font_design)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                } else {
                    List {
                        ForEach(favorites_sorted) { favorite in
                            /// check if the value of the favorite train is valid
                            let is_valid: Bool = {
                                if let train_info = favorites_fetched[favorite.id], !train_info.isEmpty {
                                    return true
                                } else {
                                    return false
                                }
                            }()
                            
                            Button {
                                select_favorite(id: favorite.id)
                            } label: {
                                VStack {
                                    VStack (spacing: 16) {
                                        HStack {
                                            Image(favorite.logo)
                                                .resizable()
                                                .scaledToFit()
                                                .frame(height: UIFont.preferredFont(forTextStyle: .title3).lineHeight * 0.8)
                                            Text(favorite.number)
                                                .font(.title3)
                                                .fontWeight(.semibold)
                                            Spacer()
                                        }
                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack {
                                                Text(favorite.stop_names.first ?? "")
                                                Spacer()
                                                Text(favorite.stop_ref_times.first!.formatted(Date.FormatStyle.dateTime.hour().minute()))
                                            }
                                            HStack {
                                                Text(favorite.stop_names.last ?? "")
                                                Spacer()
                                                Text(favorite.stop_ref_times.last!.formatted(Date.FormatStyle.dateTime.hour().minute()))
                                            }
                                        }
                                        .font(.subheadline)
                                    }
                                    .fontDesign(app_font_design)
                                    .foregroundStyle(Color.primary)
                                    .padding()
                                    .contentShape(Rectangle())
                                    .background(
                                        RoundedRectangle(cornerRadius: 24)
                                            .stroke(style: favoriteID_selected == favorite.id ? StrokeStyle(lineWidth: 2) : StrokeStyle(lineWidth: 1, dash: [5]))
                                            .foregroundColor(is_valid ? (favoriteID_selected == favorite.id ? Color.accentColor : Color.primary.opacity(0.5)) : Color.red)
                                    )
                                    .opacity(favoriteID_selected == favorite.id || favoriteID_selected == nil ? 1.0 : 0.5)
                                    
                                    HStack {
                                        if !is_valid {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.callout)
                                            Text("Temporarily unavailable")
                                                .font(.footnote)
                                        }
                                    }
                                    .fontWeight(.medium)
                                    .fontDesign(app_font_design)
                                    .foregroundStyle(Color.red)
                                }
                                
                            }
                            .disabled(!is_valid)
                            .moveDisabled(!is_valid)
                            .buttonStyle(.plain)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                        }
                        .onDelete(perform: delete_favorite)
                        .onMove(perform: move_favorite)
                    }
                    .safeAreaInset(edge: .bottom) {
                        Color.clear.frame(height: 96)
                    }
                    .listStyle(.plain)
                    .scrollIndicators(.hidden)
                    .scrollContentBackground(.hidden)
                }
                
                // MARK: - bottom buttons
                if !favorites.isEmpty {
                    Button {
                        save_train()
                        dismiss()
                        favoriteID_selected = nil
                    } label: {
                        HStack {
                            Text("Save")
                            
                            Image(systemName: "checkmark")
                                .symbolEffect(.wiggle.byLayer, options: .repeat(.periodic(delay: 5.0)))
                                .contentTransition(.symbolEffect(.replace.downUp.wholeSymbol, options: .nonRepeating))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                    }
                    .font(.title3).fontWeight(.medium).fontDesign(app_font_design)
                    .buttonStyle(.glassProminent)
                    .disabled(favoriteID_selected == nil)
                    .foregroundStyle(favoriteID_selected != nil ? Color.accentColor : Color.primary)
                    .tint(favoriteID_selected != nil ? Color.accentColor.opacity(0.15) : Color.clear)
                    .padding(.bottom).padding(.horizontal)
                }
            }
            .navigationTitle("Favorites")
            .ignoresSafeArea(edges: favorites.isEmpty ? [] : .bottom)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
            }
            .onAppear {
                Task {
                    let results = await fetch_favorites(favorites: favorites)
                    self.favorites_fetched = results
                }
            }
            .onDisappear {
                favoriteID_selected = nil
            }
        }
    }
    
    // MARK: - functions
    private func delete_favorite(at offsets: IndexSet) {
        let items = offsets.map { favorites_sorted[$0] }
        for favorite in items {
            modelContext.delete(favorite)
        }
    }
    
    private func select_favorite(id: UUID) {
        if favoriteID_selected == id {
            favoriteID_selected = nil
        } else {
            favoriteID_selected = id
        }
    }
    
    private func move_favorite(from source: IndexSet, to destination: Int) {
        var items = favorites_sorted
            
        items.move(fromOffsets: source, toOffset: destination)
        for i in 0..<items.count {
            items[i].index = i
        }
        
        do {
            try modelContext.save()
        } catch {
            print("Failed to save reordered favorites: \(error)")
        }
    }
    
    private func save_train() {
        // unique id for train and stops
        let id = UUID()
        
        // MARK: - add train
        /// get selected train
        let favorite_selected = favorites_fetched.filter { $0.key == favoriteID_selected }.first
        
        /// get details
        let logo = favorite_selected?.value["logo"] as? String ?? ""
        let number = favorite_selected?.value["number"] as? String ?? ""
        let identifier = favorite_selected?.value["identifier"] as? String ?? ""
        let provider = favorite_selected?.value["provider"] as? String ?? ""
        
        let last_update_time = favorite_selected?.value["last_update_time"] as? Date ?? Date()
        let delay = favorite_selected?.value["delay"] as? Int ?? 0
        let direction = favorite_selected?.value["direction"] as? String ?? ""
        
        let issue = favorite_selected?.value["issue"] as? String ?? ""
        
        /// save to database
        let train_to_add = Train(
            id: id,
            logo: logo,
            number: number,
            identifier: identifier,
            provider: provider,
            last_update_time: last_update_time,
            delay: delay,
            direction: direction,
            issue: issue
        )
        modelContext.insert(train_to_add)
        
        // MARK: - add stops
        for stop in (favorite_selected?.value["stops"] as? [[String: Any]] ?? []) {
            /// fetch details
            let name = stop["name"] as? String ?? ""
            let platform = stop["platform"] as? String ?? ""
            let weather = stop["weather"] as? String ?? ""
            
            let is_selected = stop["is_selected"] as? Bool ?? false
            let status = stop["status"] as? Int ?? 0
            let is_completed = stop["is_completed"] as? Bool ?? false
            let is_in_station = stop["is_in_station"] as? Bool ?? false
            
            let dep_delay = stop["dep_delay"] as? Int ?? 0
            let arr_delay = stop["arr_delay"] as? Int ?? 0
            
            let dep_time_id = stop["dep_time_id"] as? Date ?? .distantPast
            let dep_time_eff = stop["dep_time_eff"] as? Date ?? .distantPast
            let arr_time_id = stop["arr_time_id"] as? Date ?? .distantPast
            let arr_time_eff = stop["arr_time_eff"] as? Date ?? .distantPast
            let ref_time = stop["ref_time"] as? Date ?? .distantPast
            
            /// save to database
            let stop_to_add = Stop(
                id: id,
                name: name,
                platform: platform,
                weather: weather,
                is_selected: is_selected,
                status: status,
                is_completed: is_completed,
                is_in_station: is_in_station,
                dep_delay: dep_delay,
                arr_delay: arr_delay,
                dep_time_id: dep_time_id,
                arr_time_id: arr_time_id,
                dep_time_eff: dep_time_eff,
                arr_time_eff: arr_time_eff,
                ref_time: ref_time
            )
            modelContext.insert(stop_to_add)
        }
        
        print("\n ✅ Train and stops saved successfully!")
    }
}

// MARK: - shared functions
func fetch_favorites(favorites: [Favorite]) async -> [UUID: [String: Any]] {
    var temp_fetched: [UUID: [String: Any]] = [:]
    
    for favorite in favorites {
        let identifier: String = {
            if favorite.provider == "trenitalia" {
                let today_timestamp = Int(Date().timeIntervalSince1970) * 1000
                return "\(favorite.identifier)/\(today_timestamp)"
            } else {
                return favorite.identifier
            }
        }()
        
        var train_info = await {
            if favorite.provider == "trenitalia" {
                return await TrenitaliaAPI().info(identifier: identifier, should_fetch_weather: true)
            } else if favorite.provider == "italo" {
                return await ItaloAPI().info(identifier: identifier)
            } else {
                return nil
            }
        }()
        
        if var info = train_info {
            if let fetchedStops = info["stops"] as? [[String: Any]] {
                let modifiedStops = fetchedStops.map { stop -> [String: Any] in
                    var modifiedStop = stop
                    let name = stop["name"] as? String ?? ""
                    modifiedStop["is_selected"] = favorite.stop_names.contains(name)
                    return modifiedStop
                }
                info["stops"] = modifiedStops
                train_info = info
            }
        }
        
        temp_fetched[favorite.id] = train_info ?? [:]
    }
    
    print("🔄 Favorites fetched successfully!")
    return temp_fetched
}


// MARK: - previews
#Preview("Add Favorites View - Full") {
    // memory container
    let schema = Schema([Favorite.self])
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: config)
    
    // mock data
    let fav1 = Favorite(
        id: UUID(),
        index: 0,
        identifier: "frecciarossa",
        provider: "trenitalia",
        logo: "FR",
        number: "9607",
        stop_names: ["Torino Porta Nuova", "Napoli Centrale"],
        stop_ref_times: [
            Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: Date())!,
            Calendar.current.date(bySettingHour: 15, minute: 45, second: 0, of: Date())!
        ]
    )
    let fav2 = Favorite(
        id: UUID(),
        index: 0,
        identifier: "it1234",
        provider: "italo",
        logo: "Italo",
        number: "1234",
        stop_names: ["Milano Centrale", "Roma Termini"],
        stop_ref_times: [
            Calendar.current.date(bySettingHour: 9, minute: 30, second: 0, of: Date())!,
            Calendar.current.date(bySettingHour: 14, minute: 15, second: 0, of: Date())!
        ]
    )
    let fav3 = Favorite(
        id: UUID(),
        index: 0,
        identifier: "frecciargento",
        provider: "trenitalia",
        logo: "RV",
        number: "8840",
        stop_names: ["Bologna Centrale", "Salerno"],
        stop_ref_times: [
            Calendar.current.date(bySettingHour: 11, minute: 15, second: 0, of: Date())!,
            Calendar.current.date(bySettingHour: 16, minute: 50, second: 0, of: Date())!
        ]
    )
    let fav4 = Favorite(
        id: UUID(),
        index: 0,
        identifier: "frecciargento",
        provider: "trenitalia",
        logo: "RV",
        number: "8840",
        stop_names: ["Bologna Centrale", "Salerno"],
        stop_ref_times: [
            Calendar.current.date(bySettingHour: 11, minute: 15, second: 0, of: Date())!,
            Calendar.current.date(bySettingHour: 16, minute: 50, second: 0, of: Date())!
        ]
    )
    let fav5 = Favorite(
        id: UUID(),
        index: 0,
        identifier: "frecciargento",
        provider: "trenitalia",
        logo: "RV",
        number: "8840",
        stop_names: ["Bologna Centrale", "Salerno"],
        stop_ref_times: [
            Calendar.current.date(bySettingHour: 11, minute: 15, second: 0, of: Date())!,
            Calendar.current.date(bySettingHour: 16, minute: 50, second: 0, of: Date())!
        ]
    )
    let fav6 = Favorite(
        id: UUID(),
        index: 0,
        identifier: "frecciargento",
        provider: "trenitalia",
        logo: "RV",
        number: "8840",
        stop_names: ["Bologna Centrale", "Salerno"],
        stop_ref_times: [
            Calendar.current.date(bySettingHour: 11, minute: 15, second: 0, of: Date())!,
            Calendar.current.date(bySettingHour: 16, minute: 50, second: 0, of: Date())!
        ]
    )
    
    container.mainContext.insert(fav1)
    container.mainContext.insert(fav2)
    container.mainContext.insert(fav3)
    container.mainContext.insert(fav4)
    container.mainContext.insert(fav5)
    container.mainContext.insert(fav6)
    
    // view
    return AddFavoriteView(favorites_fetched: .constant([:]), favoriteID_selected: .constant(nil))
        .modelContainer(container)
}

#Preview("Add Favorites View - Empty") {
    // memory container
    let schema = Schema([Favorite.self])
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: config)
    
    // view
    return AddFavoriteView(favorites_fetched: .constant([:]), favoriteID_selected: .constant(nil))
        .modelContainer(container)
}
