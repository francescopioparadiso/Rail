import SwiftUI
import SwiftData

enum current_view: String {
    case add_train = "Add Train"
    case choose_train = "Choose Train"
    case choose_stops = "Choose Stops"
    case choose_date = "Choose Date"
}
enum current_provider {
    case trenitalia
    case italo
}
enum current_fetching: CaseIterable {
    case idle
    case fetching
    case success
    case failure
    
    var title: String {
        switch self {
        case .idle, .success:
            return ""
        case .fetching:
            return "Searching solutions..."
        case .failure:
            return "No solutions found"
        }
    }
    
    var icon: String {
        switch self {
        case .idle, .success:
            return ""
        case .fetching:
            return "text.magnifyingglass"
        case .failure:
            return "exclamationmark.triangle.fill"
        }
    }
    
    var description: String {
        switch self {
        case .idle, .fetching, .success:
            return ""
        case .failure:
            return "Try checking the train number and your internet connection."
        }
    }
    
    var color: Color {
        switch self {
        case .idle, .success:
            return Color.primary
        case .fetching:
            return Color.accentColor
        case .failure:
            return Color.red
        }
    }
}

struct AddTrainView: View {
    // MARK: - variables
    // enviroment variables
    @Environment(\.requestReview) var requestReview
    @Environment(\.dismiss) private var dismiss
    
    // database variables
    @Environment(\.modelContext) private var modelContext
    @Query private var trains: [Train]
    @Query private var stops: [Stop]
    
    // view state
    @State private var current_view: current_view = .add_train
    @State private var current_provider: current_provider = .trenitalia
    @State private var current_fetching: current_fetching = .idle
    
    // focus variables
    @FocusState private var is_focused: Bool
    
    // train search variables
    @State private var trains_fetched: [UUID: [String: Any]] = [:]
    @State private var trainID_selected: UUID? = nil
    @State private var stops_fetched: [[String: Any]] = []
    @State private var stops_selected: [[String: Any]] = []
    
    @State private var train_number: String = ""
    @State private var date_selected: Date = Date()
    
    // button properties
    private var back_button_icon: String {
        switch current_view {
        case .add_train:
            return "xmark"
        case .choose_train, .choose_stops, .choose_date:
            return "chevron.left"
        }
    }
    private var next_button_icon: String {
        switch current_view {
        case .add_train, .choose_train, .choose_stops:
            return "chevron.right"
        case .choose_date:
            return "checkmark"
        }
    }
    private var button_is_active: Bool {
        switch current_view {
        case .add_train:
            return !train_number.isEmpty
            
        case .choose_train:
            return trainID_selected != nil
            
        case .choose_stops:
            return stops_selected.count >= 2
            
        case .choose_date:
            return true
        }
    }
    
    // MARK: - main view
    var body: some View {
        NavigationStack {
            VStack {
                switch current_view {
                case .add_train:
                    add_train_view()
                    
                case .choose_train:
                    choose_train_view()
                    
                case .choose_stops:
                    choose_stops_view()
                    
                case .choose_date:
                    choose_date_view()
                }
            }
            .navigationTitle(current_view.rawValue)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // back or dismiss button
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        back_button_action()
                    } label: {
                        Image(systemName: back_button_icon)
                            .contentTransition(.symbolEffect(.replace.downUp.wholeSymbol, options: .nonRepeating))
                    }
                }
                
                // next or save button
                ToolbarItem(placement: .navigationBarTrailing) {
                    switch button_is_active {
                        case true:
                            Button {
                                next_button_action()
                            } label: {
                                Image(systemName: next_button_icon)
                                    .contentTransition(.symbolEffect(.replace.downUp.wholeSymbol, options: .nonRepeating))
                            }
                            .buttonStyle(.glassProminent)
                        
                        case false:
                            Button {
                                next_button_action()
                            } label: {
                                Image(systemName: next_button_icon)
                                    .contentTransition(.symbolEffect(.replace.downUp.wholeSymbol, options: .nonRepeating))
                            }
                            .disabled(true)
                    }
                }
            }
        }
        .onAppear {
            is_focused = true
            ReviewManager.shared.requestReviewIfAppropriate(action: requestReview)
        }
        .onChange(of: current_fetching) { old_value, new_value in
            // timer to prevent infinite fetching state
            if old_value == .idle && new_value == .fetching {
                DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
                    if current_fetching == .fetching {
                        current_fetching = .failure
                    }
                }
            }
        }
    }
    
    // MARK: - views functions
    @ViewBuilder func add_train_view() -> some View {
        VStack {
            TextField("0", text: $train_number)
                .font(.system(size: 80))
                .fontDesign(appFontDesign)
                .fontWeight(.bold)
            
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .focused($is_focused)
                
                .padding()
            
            Spacer()
        }
        .padding()
    }
    
    @ViewBuilder func choose_train_view() -> some View {
        switch current_fetching {
        case .idle:
            EmptyView()
            
        case .fetching:
            ContentUnavailableView {
                Label {
                    Text(current_fetching.title)
                } icon: {
                    Image(systemName: current_fetching.icon)
                        .symbolEffect(.breathe.pulse.wholeSymbol, options: .repeat(.continuous))
                }
            }
            .padding()
            .foregroundColor(current_fetching.color)
            
        case .success:
            VStack {
                ForEach(Array(trains_fetched.keys).enumerated(), id: \.element) { index, id in
                    // get useful parameter for displaying
                    let number = trains_fetched[id]?["number"] as? String ?? ""
                    let logo = trains_fetched[id]?["logo"] as? String ?? ""
                    
                    let stops = trains_fetched[id]?["stops"] as? [[String: Any]] ?? []
                    let firstStop_name = stops.first?["name"] as? String ?? ""
                    let lastStop_name = stops.last?["name"] as? String ?? ""
                    let firstStop_refTime = stops.first?["ref_time"] as? Date ?? .distantPast
                    let lastStop_refTime = stops.last?["ref_time"] as? Date ?? .distantPast
                    
                    // display button for each train
                    Button {
                        /// toggle behavior
                        if trainID_selected == id {
                            trainID_selected = nil
                        } else {
                            trainID_selected = id
                        }
                        
                    } label: {
                        VStack (spacing: 16) {
                            /// logo +  number
                            HStack {
                                Image(logo)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(height: UIFont.preferredFont(forTextStyle: .title3).lineHeight * 0.8)
                                
                                Text(number)
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                
                                Spacer()
                            }
                            
                            /// departure and arrival stop name + time
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(firstStop_name)
                                    Spacer()
                                    Text(firstStop_refTime.formatted(Date.FormatStyle.dateTime.hour().minute()))
                                }
                                
                                HStack {
                                    Text(lastStop_name)
                                    Spacer()
                                    Text(lastStop_refTime.formatted(Date.FormatStyle.dateTime.hour().minute()))
                                }
                            }
                            .font(.subheadline)
                        }
                        .fontDesign(appFontDesign)
                        .foregroundStyle(Color.primary)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 24)
                                .stroke(style: trainID_selected == id ? StrokeStyle(lineWidth: 2) : StrokeStyle(lineWidth: 1, dash: [5]))
                                .foregroundColor( trainID_selected == id ? Color.accentColor : Color.primary.opacity(0.5))
                        )
                    }
                    .padding()
                }
                
                Spacer()
            }
            
        case .failure:
            ContentUnavailableView(
                current_fetching.title,
                systemImage: current_fetching.icon,
                description: Text(current_fetching.description)
            )
            .padding()
            .foregroundColor(current_fetching.color)
        }
    }
    
    @ViewBuilder func choose_stops_view() -> some View {
        ZStack(alignment: .bottom) {
            VStack {
                List {
                    ForEach(stops_fetched.enumerated(), id: \.offset) { index, stop in
                        let name = stop["name"] as? String ?? ""
                        let ref_time = stop["ref_time"] as? Date ?? .distantPast
                        
                        let is_selected = stops_selected.contains(where: { $0["name"] as? String == name })
                        
                        Button {
                            stops_selected = select_stops(stopsFetched: stops_fetched, currentSelection: stops_selected, tappedIndex: index)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: is_selected ? "checkmark.circle.fill" : "circle")
                                    .font(.title)
                                    .foregroundStyle(is_selected ? Color.accentColor : Color.primary)
                                    .contentTransition(.symbolEffect(.replace.downUp.wholeSymbol, options: .nonRepeating))
                                
                                Text(name)
                                    .font(.subheadline)
                                    .lineLimit(2)
                                    .truncationMode(.tail)
                                    .minimumScaleFactor(0.5)
                                
                                Spacer(minLength: 16)
                                
                                Text(ref_time.formatted(Date.FormatStyle.dateTime.hour().minute()))
                                    .font(.subheadline)
                            }
                            .fontDesign(appFontDesign)
                            .foregroundStyle(Color.primary)
                            .padding(4)
                            .contentShape(Rectangle())
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .scrollIndicators(.hidden)
                
                Spacer()
            }
            .padding(.horizontal, 0).padding(.top, 0).padding(.bottom, 96)
            
            // select/deselect all button
            Button {
                if stops_selected.count < stops_fetched.count {
                    stops_selected = stops_fetched
                } else {
                    stops_selected.removeAll()
                }
            } label: {
                HStack {
                    Image(systemName: stops_selected.count < stops_fetched.count ? "circle" : "checkmark.circle.fill")
                        .font(.largeTitle)
                        .padding(.vertical).padding(.leading)
                        .contentTransition(.symbolEffect(.replace.downUp.wholeSymbol, options: .nonRepeating))
                    
                    Text(stops_selected.count < stops_fetched.count ? "Select All Stops" : "Deselect All Stops")
                        .font(.footnote)
                        .multilineTextAlignment(.leading)
                        .padding(.vertical).padding(.trailing)
                        .contentTransition(.numericText(value: Double(stops_selected.count)))
                        .animation(.easeInOut, value: stops_selected.count)
                    
                    Spacer(minLength: 0)
                }
                .fontDesign(appFontDesign)
                .foregroundStyle(Color.accentColor)
            }
            .frame(maxWidth: .infinity)
            .buttonStyle(.glassProminent)
            .tint(Color.accentColor.opacity(0.15))
            .padding(.bottom).padding(.horizontal)
        }
        .background(Color(UIColor.systemBackground))
        .ignoresSafeArea(edges: .bottom)
        .toolbar(.hidden, for: .tabBar)
    }
    
    @ViewBuilder func choose_date_view() -> some View {
        VStack {
            DatePicker("", selection: $date_selected, in: Date()..., displayedComponents: [.date])
                .datePickerStyle(GraphicalDatePickerStyle())
            
            Spacer()
        }
        .padding(8)
    }
    
    // MARK: - button functions
    private func back_button_action() {
        switch current_view {
        case .add_train:
            /// haptic feedback
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            
            /// change view
            dismiss()
            
            /// reset variables
            trains_fetched = [:]
            train_number = ""
            trainID_selected = nil
            date_selected = Date()
            
        case .choose_train:
            /// haptic feedback
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            
            /// update focus
            is_focused = true
            
            /// change view
            current_view = .add_train
            
            /// reset variables
            trains_fetched = [:]
            trainID_selected = nil
            
            /// fetching status
            current_fetching = .idle
            
        case .choose_stops:
            /// haptic feedback
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            
            /// change view
            current_view = .choose_train
            
            /// reset variables
            stops_selected.removeAll()
            
        case .choose_date:
            /// haptic feedback
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            
            /// change view
            current_view = .choose_stops
            
            /// reset variables
            date_selected = Date()
        }
    }
    private func next_button_action() {
        switch current_view {
        case .add_train:
            /// haptic feedback
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            
            /// change view
            current_view = .choose_train
            
            /// actions
            Task { await fetch_trains() }
            
        case .choose_train:
            /// haptic feedback
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            
            /// change view
            current_view = .choose_stops
            
            /// actions
            save_stops()
            
        case .choose_stops:
            /// haptic feedback
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            
            /// change view
            current_view = .choose_date
            
        case .choose_date:
            /// haptic feedback
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            
            /// actions
            save_train()
            
            /// change view
            dismiss()
        }
    }
    
    // MARK: - fetching functions
    private func fetch_trains() async {
        // fetching status
        current_fetching = .fetching
        
        // fetching process
        Task {
            /// fetch from both providers
            let results = await fetch_common_train_list(number : train_number)
            
            /// assign results to variables
            for result in results {
                trains_fetched[UUID()] = result
            }
            
            /// define fetching status again
            await MainActor.run {
                if trains_fetched.isEmpty {
                    current_fetching = .failure
                } else {
                    current_fetching = .success
                }
            }
        }
    }
    private func save_stops() {
        let train = trains_fetched.filter { $0.key == trainID_selected }.first
        let stops = train?.value["stops"] as? [[String: Any]] ?? []
        for stop in stops {
            stops_fetched.append(stop)
        }
    }
    private func select_stops(stopsFetched: [[String: Any]], currentSelection: [[String: Any]], tappedIndex: Int) -> [[String: Any]] {
        let selectedIndices: [Int] = currentSelection.compactMap { selected in
            guard let name = selected["name"] as? String else { return nil }
            return stopsFetched.firstIndex(where: {
                ($0["name"] as? String) == name
            })
        }.sorted()

        let lowerBound = selectedIndices.first
        let upperBound = selectedIndices.last

        let isSelected = selectedIndices.contains(tappedIndex)

        if isSelected {
            /// Shrink range
            guard let lower = lowerBound else { return [] }

            let newUpper = tappedIndex - 1
            if newUpper >= lower {
                return Array(stopsFetched[lower...newUpper])
            } else {
                return []
            }
        } else {
            /// Extend range
            if let lower = lowerBound, let upper = upperBound {
                let newLower = Swift.min(lower, tappedIndex)
                let newUpper = Swift.max(upper, tappedIndex)
                return Array(stopsFetched[newLower...newUpper])
            } else {
                return [stopsFetched[tappedIndex]]
            }
        }
    }
    private func save_train() {
        // unique id for train and stops
        let id = UUID()
        
        // MARK: - day difference for future dates
        /// get the first stop selected reference time
        let firstStop_refTime = stops_fetched.first?["ref_time"] as? Date ?? .distantPast
        
        /// compare its day with the selected date
        let startOfDay_dateSelected = Calendar.current.startOfDay(for: date_selected)
        let startOfDay_firstStop_refTime = Calendar.current.startOfDay(for: firstStop_refTime)
        
        /// calculate the day difference
        let day_difference = abs(Calendar.current.dateComponents([.day], from: startOfDay_dateSelected, to: startOfDay_firstStop_refTime).day ?? 0)
        
        // MARK: - add train
        /// get selected train
        let train_selected = trains_fetched.filter { $0.key == trainID_selected }.first
        
        /// get details
        let logo = train_selected?.value["logo"] as? String ?? ""
        let number = train_selected?.value["number"] as? String ?? ""
        let identifier = train_selected?.value["identifier"] as? String ?? ""
        let provider = train_selected?.value["provider"] as? String ?? ""
        
        let last_update_time = train_selected?.value["last_update_time"] as? Date ?? Date()
        let delay = train_selected?.value["delay"] as? Int ?? 0
        let direction = train_selected?.value["direction"] as? String ?? ""
        
        let seats = train_selected?.value["seats"] as? [String] ?? []
        let issue = train_selected?.value["issue"] as? String ?? ""

        /// adjust identifier timestamp based on day difference
        let identifier_string: String = {
            guard provider != "italo" else { return train_number }
            
            let components = identifier.split(separator: "/").map { String($0) }
            var timestamp = Int(components.last ?? "") ?? 0
            let adjustedDate = Date(timeIntervalSince1970: TimeInterval(timestamp)).addingTimeInterval(TimeInterval(day_difference) * 86_400)
            timestamp = Int(adjustedDate.timeIntervalSince1970)
            return components.dropLast().joined(separator: "/") + "/\(timestamp)"
        }()
        print(identifier_string)
        
        /// save to database
        let train_to_add = Train(
            id: id,
            logo: logo,
            number: number,
            identifier: identifier_string,
            provider: provider,
            last_update_time: last_update_time,
            delay: delay,
            direction: direction,
            seats: seats,
            issue: issue
        )
        modelContext.insert(train_to_add)
        
        // MARK: - add stops
        for stop in stops_fetched {
            /// fetch details
            let name = stop["name"] as? String ?? ""
            let platform = stop["platform"] as? String ?? ""
            let weather = stop["weather"] as? String ?? ""
            
            let is_selected = stops_selected.contains(where: { $0["name"] as? String == name })
            let status = stop["status"] as? Int ?? 0
            let is_completed = stop["is_completed"] as? Bool ?? false
            let is_in_station = stop["is_in_station"] as? Bool ?? false
            
            let dep_delay = stop["dep_delay"] as? Int ?? 0
            let arr_delay = stop["arr_delay"] as? Int ?? 0
            
            var dep_time_id = stop["dep_time_id"] as? Date ?? .distantPast
            var dep_time_eff = stop["dep_time_eff"] as? Date ?? .distantPast
            var arr_time_id = stop["arr_time_id"] as? Date ?? .distantPast
            var arr_time_eff = stop["arr_time_eff"] as? Date ?? .distantPast
            var ref_time = stop["ref_time"] as? Date ?? .distantPast
            
            /// adjust timestamps based on day difference
            dep_time_id.addTimeInterval(TimeInterval(day_difference) * 86_400)
            dep_time_eff.addTimeInterval(TimeInterval(day_difference) * 86_400)
            arr_time_id.addTimeInterval(TimeInterval(day_difference) * 86_400)
            arr_time_eff.addTimeInterval(TimeInterval(day_difference) * 86_400)
            ref_time.addTimeInterval(TimeInterval(day_difference) * 86_400)
            
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
