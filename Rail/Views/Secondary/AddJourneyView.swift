import SwiftUI
import SwiftData

enum Field {
    case number
    case train
    case stops
    case date
}

enum Views: String {
    case add_number = "Add train number"
    case choose_train = "Choose train"
    case choose_stops = "Choose stops"
    case choose_date = "Choose date"
}

struct AddJourneyView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var trains: [Train]
    @Query private var stops: [Stop]
    
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?
    @State private var actualView: Views = .add_number

    @State private var train_number: String = ""

    @State private var train_results: [UUID: [String: Any]] = [:]
    @State private var train_selected: [UUID: [String: Any]] = [:]
    @State private var stop_results: [UUID: [[String: Any]]] = [:]
    @State private var stop_selected: [UUID: [[String: Any]]] = [:]
    
    @State private var id_selected: String = ""
    @State private var date_selected: Date = Date()
    
    @State private var is_loading: Bool = false
    @State private var stop_selected_count: Int = 0

    var body: some View {
        // close sheet button on the left and send button on the right
        NavigationStack {
            VStack {
                switch actualView {
                case .add_number:
                    NumberView()
                case .choose_train:
                    TrainsView()
                case .choose_stops:
                    StopsView()
                case .choose_date:
                    DateView()
                }
            }
            .navigationTitle(NSLocalizedString(actualView.rawValue, comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // back or dismiss button
                ToolbarItem(placement: .navigationBarLeading) {
                    let icon =  {
                        switch actualView {
                        case .add_number:
                            return "xmark"
                        case .choose_train, .choose_stops, .choose_date:
                            return "chevron.left"
                        }
                    }()
                    
                    Button {
                        switch actualView {
                        case .add_number:
                            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                            dismiss()
                        case .choose_train:
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            train_results = [:]
                            stop_results = [:]
                            
                            if let lastTrainID = Array(train_selected.keys).last {
                                train_selected.removeValue(forKey: lastTrainID)
                            }

                            if let lastStopID = Array(stop_selected.keys).last {
                                stop_selected.removeValue(forKey: lastStopID)
                            }
                            
                            id_selected = ""
                            
                            actualView = .add_number
                            focusedField = .number
                        case .choose_stops:
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            stop_selected.removeAll()
                            
                            actualView = .choose_train
                        case .choose_date:
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            actualView = .choose_stops
                        }
                    } label: {
                        Image(systemName: icon)
                            .contentTransition(.symbolEffect(.replace.downUp.wholeSymbol, options: .nonRepeating))
                    }
                }
                
                // next or save button
                ToolbarItem(placement: .navigationBarTrailing) {
                    switch actualView {
                    case .add_number:
                        if train_number.count >= 2 {
                            Button {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                train_results = [:]
                                stop_results = [:]
                                is_loading = true

                                let start = CFAbsoluteTimeGetCurrent()
                                let timeoutInterval: Double = 10.0

                                DispatchQueue.main.asyncAfter(deadline: .now() + timeoutInterval) {
                                    if self.is_loading {
                                        self.is_loading = false
                                        print("🚨 Fetching timed out after \(timeoutInterval) seconds.")
                                    }
                                }

                                fetch_train_list(number: train_number) { trains in
                                    DispatchQueue.global(qos: .userInitiated).async {

                                        var newTrainResults = [UUID: [String: Any]]()
                                        var newStopResults = [UUID: [[String: Any]]]()

                                        for train in trains {
                                            if train["number"] as? String == train_number {
                                                let id = UUID()
                                                newTrainResults[id] = train
                                                if let stops = train["stops"] as? [[String: Any]] {
                                                    newStopResults[id] = stops
                                                }
                                            }
                                        }

                                        DispatchQueue.main.async {
                                            if self.is_loading {
                                                self.train_results = newTrainResults
                                                self.stop_results = newStopResults
                                                self.is_loading = false

                                                let diff = CFAbsoluteTimeGetCurrent() - start
                                                print("⏱️ Fetching train list took \(Int(diff))s \(Int((diff - Double(Int(diff))) * 1000))ms")
                                            }
                                        }
                                    }
                                }

                                actualView = .choose_train
                            } label: {
                                Image(systemName: "chevron.right")
                            }
                            .buttonStyle(.glassProminent)
                        } else {
                            Button {
                                train_results = [:]
                                stop_results = [:]
                                is_loading = true

                                let start = CFAbsoluteTimeGetCurrent()
                                let timeoutInterval: Double = 4.0

                                DispatchQueue.main.asyncAfter(deadline: .now() + timeoutInterval) {
                                    if self.is_loading {
                                        self.is_loading = false
                                        print("🚨 Fetching timed out after \(timeoutInterval) seconds.")
                                    }
                                }

                                fetch_train_list(number: train_number) { trains in
                                    DispatchQueue.global(qos: .userInitiated).async {

                                        var newTrainResults = [UUID: [String: Any]]()
                                        var newStopResults = [UUID: [[String: Any]]]()

                                        for train in trains {
                                            if train["number"] as? String == train_number {
                                                let id = UUID()
                                                newTrainResults[id] = train
                                                if let stops = train["stops"] as? [[String: Any]] {
                                                    newStopResults[id] = stops
                                                }
                                            }
                                        }

                                        DispatchQueue.main.async {
                                            if self.is_loading {
                                                self.train_results = newTrainResults
                                                self.stop_results = newStopResults
                                                self.is_loading = false

                                                let diff = CFAbsoluteTimeGetCurrent() - start
                                                print("⏱️ Fetching train list took \(Int(diff))s \(Int((diff - Double(Int(diff))) * 1000))ms")
                                            }
                                        }
                                    }
                                }

                                actualView = .choose_train
                            } label: {
                                Image(systemName: "chevron.right")
                            }
                            .disabled(train_number.count < 2)
                        }
                    case .choose_train:
                        if id_selected != "" {
                            Button {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                if let id = UUID(uuidString: id_selected), let selected = train_results[id] {
                                    train_selected[id] = selected
                                }
                                actualView = .choose_stops
                            } label: {
                                Image(systemName: "chevron.right")
                            }
                            .buttonStyle(.glassProminent)
                        } else {
                            Button {
                                if let id = UUID(uuidString: id_selected), let selected = train_results[id] {
                                    train_selected[id] = selected
                                }
                                actualView = .choose_stops
                            } label: {
                                Image(systemName: "chevron.right")
                            }
                            .disabled(id_selected == "")
                        }
                    case .choose_stops:
                        if stop_selected_count >= 2 {
                            Button {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                if let id = UUID(uuidString: id_selected), let selected = stop_selected[id], !selected.isEmpty {
                                    stop_selected[id] = selected
                                }
                                actualView = .choose_date
                            } label: {
                                Image(systemName: "chevron.right")
                            }
                            .buttonStyle(.glassProminent)
                        } else {
                            Button {
                                if let id = UUID(uuidString: id_selected), let selected = stop_selected[id], !selected.isEmpty {
                                    stop_selected[id] = selected
                                }
                                actualView = .choose_date
                            } label: {
                                Image(systemName: "chevron.right")
                            }
                            .disabled(stop_selected_count < 2)
                        }
                    case .choose_date:
                        Button {
                            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                            add_to_database()
                            dismiss()
                            train_results.removeAll()
                            stop_results.removeAll()
                        } label: {
                            Text("Save")
                                .fontDesign(appFontDesign)
                        }
                        .buttonStyle(.glassProminent)
                    }
                }
            }
            .onChange(of: actualView) { _, newValue in
                print("\n🟩 ACTUAL VIEW: \(newValue)----------------------------------------------------------------------")
                print("\n   🚆 train results:\n \(train_results)")
                print("\n   🚆 train selected:\n \(train_selected)")
                print("\n   🚏 stop results:\n \(stop_results)")
                print("\n   🚏 stop selected:\n \(stop_selected)")
                print("\n   ℹ️ id selected: \(id_selected)")
                print("\n   ℹ️ stop_selected_count: \(stop_selected_count)")
            }
        }
        .onAppear {
            focusedField = .number
        }
    }

    @ViewBuilder 
    private func NumberView() -> some View {
        VStack {
            TextField("0", text: $train_number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .padding()
                .font(.system(size: 64))
                .fontDesign(appFontDesign)
                .fontWeight(.bold)
                .focused($focusedField, equals: .number)
                .onSubmit {
                    focusedField = .train
                    actualView = .choose_train
                }
            Spacer()
            
        }
        .padding()
    }

    @ViewBuilder 
    private func TrainsView() -> some View {
        VStack(spacing: 16) {
            if is_loading {
                ContentUnavailableView {
                    Label {
                        Text("Searching train number...")
                            .foregroundColor(Color.primary)
                    } icon: {
                        Image(systemName: "text.magnifyingglass")
                            .symbolEffect(.breathe.pulse.wholeSymbol, options: .repeat(.continuous))
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .padding()
            } else if train_results.isEmpty {
                ContentUnavailableView(
                    "No trains found",
                    systemImage: "exclamationmark.triangle.fill",
                    description: Text("Try checking the train number and your internet connection.")
                )
                .padding()
                .foregroundColor(Color.red)
            } else {
                ForEach(Array(train_results.keys), id: \.self) { trainID in
                    let number = train_results[trainID]!["number"] as? String ?? ""
                    let logo = train_results[trainID]!["logo"] as? String ?? ""
                    
                    let stops = stop_results[trainID] ?? []
                    let first_stop_name = (stops.first?["name"] as? String) ?? ""
                    let last_stop_name = (stops.last?["name"] as? String) ?? ""
                    let first_stop_ref_time = (stops.first?["ref_time"] as? Date) ?? .distantPast
                    let last_stop_ref_time = (stops.last?["ref_time"] as? Date) ?? .distantPast
                    
                    Button {
                        if id_selected != trainID.uuidString {
                            id_selected = trainID.uuidString
                        } else {
                            id_selected = ""
                        }
                    } label: {
                        VStack (spacing: 16) {
                            HStack {
                                Image(logo)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(height: UIFont.preferredFont(forTextStyle: .title3).lineHeight * 0.8)
                                
                                Text(number)
                                    .font(.title3)
                                    .fontDesign(appFontDesign)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Color.primary)
                                
                                Spacer()
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(first_stop_name)
                                        .font(.subheadline)
                                        .fontDesign(appFontDesign)
                                        .foregroundStyle(Color.primary)
                                    
                                    Spacer()
                                    
                                    Text(first_stop_ref_time.formatted(Date.FormatStyle.dateTime.hour().minute()))
                                        .font(.subheadline)
                                        .fontDesign(appFontDesign)
                                        .foregroundStyle(Color.primary)
                                }
                                
                                HStack {
                                    Text(last_stop_name)
                                        .font(.subheadline)
                                        .fontDesign(appFontDesign)
                                        .foregroundStyle(Color.primary)
                                    
                                    Spacer()
                                    
                                    Text(last_stop_ref_time.formatted(Date.FormatStyle.dateTime.hour().minute()))
                                        .font(.subheadline)
                                        .fontDesign(appFontDesign)
                                        .foregroundStyle(Color.primary)
                                }
                            }
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 24)
                                .stroke(style: id_selected == trainID.uuidString ? StrokeStyle(lineWidth: 2) : StrokeStyle(lineWidth: 1, dash: [5]))
                                .foregroundColor(id_selected == trainID.uuidString ? Color.accentColor : Color.primary.opacity(0.5))
                        )
                    }
                }
            }

            Spacer()
        }
        .padding()
    }

    @ViewBuilder
    private func StopsView() -> some View {
        let selectedID = UUID(uuidString: id_selected)
        let stops = selectedID.flatMap { stop_results[$0] } ?? []

        List {
            ForEach(Array(stops.enumerated()), id: \.offset) { index, stop in
                let name = stop["name"] as? String ?? ""
                let ref_time = stop["ref_time"] as? Date ?? Date()
                let isSelected: Bool = {
                    guard let id = selectedID, let selected = stop_selected[id] else { return false }
                    return selected.contains(where: { stopsEqual($0, stop) })
                }()
                
                HStack(spacing: 8) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title)
                        .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                    
                    Text(name)
                        .font(.subheadline)
                        .fontDesign(appFontDesign)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .minimumScaleFactor(0.5)
                    
                    Spacer(minLength: 16)
                    
                    Text(ref_time.formatted(Date.FormatStyle.dateTime.hour().minute()))
                        .font(.subheadline)
                        .fontDesign(appFontDesign)
                }
                .padding(4)
                .contentShape(Rectangle())
                .onTapGesture {
                    guard let id = selectedID else { return }

                    toggleStopSelection(stop, for: id)

                    if let selected = stop_selected[id] {
                        stop_selected_count = selected.count
                    } else {
                        stop_selected_count = 0
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private func DateView() -> some View {
        VStack {
            DatePicker("", selection: $date_selected, in: Date()..., displayedComponents: [.date])
                .datePickerStyle(GraphicalDatePickerStyle())
            
            Spacer()
        }
        .padding()
    }
    

    private func stopsEqual(_ a: [String: Any], _ b: [String: Any]) -> Bool {
        let nameA = a["name"] as? String
        let nameB = b["name"] as? String
        let timeA = a["ref_time"] as? Date
        let timeB = b["ref_time"] as? Date
        return nameA == nameB && timeA == timeB
    }

    private func toggleStopSelection(_ stop: [String: Any], for trainID: UUID) {
        // Enforce a contiguous selection range of stops for the given train.
        // Tapping outside the current range expands selection to include all stops in between.
        // Tapping inside the current range shrinks the tail to the tapped index (no gaps allowed).
        guard let allStops = stop_results[trainID] else { return }
        guard let tappedIndex = allStops.firstIndex(where: { stopsEqual($0, stop) }) else { return }

        // Map current selected stops to indices in the full stops list
        let currentSelectedStops = stop_selected[trainID] ?? []
        let selectedIndices: [Int] = currentSelectedStops.compactMap { sel in
            allStops.firstIndex(where: { stopsEqual($0, sel) })
        }.sorted()

        // If none selected, select the tapped stop
        if selectedIndices.isEmpty {
            stop_selected[trainID] = [allStops[tappedIndex]]
            return
        }

        var minIndex = selectedIndices.first!
        var maxIndex = selectedIndices.last!

        if tappedIndex < minIndex {
            // Expand selection backward to include everything up to the tapped index
            minIndex = tappedIndex
        } else if tappedIndex > maxIndex {
            // Expand selection forward to include everything up to the tapped index
            maxIndex = tappedIndex
        } else if tappedIndex == minIndex && minIndex == maxIndex {
            // Single item selected: deselect all
            stop_selected[trainID] = []
            return
        } else if tappedIndex == minIndex {
            // Shrink range from the start
            minIndex = minIndex + 1
            if minIndex > maxIndex {
                stop_selected[trainID] = []
                return
            }
        } else if tappedIndex == maxIndex {
            // Shrink range from the end
            maxIndex = maxIndex - 1
            if minIndex > maxIndex {
                stop_selected[trainID] = []
                return
            }
        } else {
            // Tapped inside the current range: shrink tail to the tapped index
            maxIndex = tappedIndex
        }

        // Apply the contiguous range [minIndex...maxIndex]
        if minIndex <= maxIndex {
            let slice = Array(allStops[minIndex...maxIndex])
            stop_selected[trainID] = slice
        } else {
            stop_selected[trainID] = []
        }
    }
    
    
    
    private func add_to_database() {
        // MARK: - sort trains
        let sortedTrainIDs = train_selected.keys.sorted { lhsID, rhsID in
            let lhsStops = stop_selected[lhsID] ?? []
            let rhsStops = stop_selected[rhsID] ?? []

            let lhsDep = lhsStops.first?["ref_time"] as? Date ?? .distantPast
            let rhsDep = rhsStops.first?["ref_time"] as? Date ?? .distantPast

            return lhsDep < rhsDep
        }
        
        // MARK: - add stops
        for trainID in sortedTrainIDs {
            var adjustedDepDates: [Date] = []

            if let stops = stop_results[trainID] {
                for (_, stopDict) in stops.enumerated() {
                    let dep_time_id = stopDict["dep_time_id"] as? Date ?? .distantPast
                    let arr_time_id = stopDict["arr_time_id"] as? Date ?? .distantPast
                    let dep_time_eff = stopDict["dep_time_eff"] as? Date ?? .distantPast
                    let arr_time_eff = stopDict["arr_time_eff"] as? Date ?? .distantPast
                    let ref_time = stopDict["ref_time"] as? Date ?? .distantPast

                    // previous adjusted date (nil for first stop)
                    let prevAdjusted = adjustedDepDates.last

                    // adjust using previous *adjusted* date
                    let dep_time_id_adjusted = adjust_date(actual_date: dep_time_id, previous_date: prevAdjusted, selected_date: date_selected)
                    let arr_time_id_adjusted = adjust_date(actual_date: arr_time_id, previous_date: prevAdjusted, selected_date: date_selected)
                    let dep_time_eff_adjusted = adjust_date(actual_date: dep_time_eff, previous_date: prevAdjusted, selected_date: date_selected)
                    let arr_time_eff_adjusted = adjust_date(actual_date: arr_time_eff, previous_date: prevAdjusted, selected_date: date_selected)
                    let ref_time_adjusted = adjust_date(actual_date: ref_time, previous_date: prevAdjusted, selected_date: date_selected)

                    // keep for next iteration (you used previous_date = ref_time_adjusted earlier)
                    adjustedDepDates.append(ref_time_adjusted)

                    print("ref_time_adjusted: \(ref_time_adjusted.formatted(Date.FormatStyle.dateTime.day().month().year().hour().minute()))")

                    let stop_to_add = Stop(
                        id: trainID,
                        name: stopDict["name"] as? String ?? "",
                        platform: stopDict["platform"] as? String ?? "-",
                        weather: stopDict["weather"] as? String ?? "",
                        is_selected: (stop_selected[trainID] ?? []).contains(where: { stopsEqual($0, stopDict) }),
                        status: stopDict["status"] as? Int ?? 0,
                        is_completed: stopDict["is_completed"] as? Bool ?? false,
                        is_in_station: stopDict["is_in_station"] as? Bool ?? false,
                        dep_delay: stopDict["dep_delay"] as? Int ?? 0,
                        arr_delay: stopDict["arr_delay"] as? Int ?? 0,
                        dep_time_id: dep_time_id_adjusted,
                        arr_time_id: arr_time_id_adjusted,
                        dep_time_eff: dep_time_eff_adjusted,
                        arr_time_eff: arr_time_eff_adjusted,
                        ref_time: ref_time_adjusted
                    )

                    modelContext.insert(stop_to_add)
                }
            }
        }

        // MARK: - insert trains
        for trainID in sortedTrainIDs {
            let identifier = {
                if train_selected[trainID]!["provider"] as? String ?? "" == "trenitalia" {
                    let old_identifier = train_selected[trainID]!["identifier"] as? String ?? ""
                    let train_number = old_identifier.split(separator: "/").first
                    let station_code = old_identifier.split(separator: "/").dropFirst().first
                    
                    let new_date_timestamp = Int(Calendar.current.startOfDay(for: date_selected).timeIntervalSince1970) * 1000
                    return "\(train_number!)/\(station_code!)/\(new_date_timestamp)"
                } else {
                    return train_selected[trainID]!["identifier"] as? String ?? ""
                }
            }()

            let train_to_add = Train(
                id: trainID,
                logo: train_selected[trainID]!["logo"] as? String ?? "",
                number: train_selected[trainID]!["number"] as? String ?? "",
                identifier: identifier,
                provider: train_selected[trainID]!["provider"] as? String ?? "",
                last_upadate_time: train_selected[trainID]!["last_upadate_time"] as? Date ?? Date(),
                delay: train_selected[trainID]!["delay"] as? Int ?? 0,
                direction: train_selected[trainID]!["direction"] as? String ?? "",
                seats: train_selected[trainID]!["seats"] as? [String] ?? [],
                issue: train_selected[trainID]!["issue"] as? String ?? ""
            )

            modelContext.insert(train_to_add)
        }
        
        print("🥳 Successfully added a new train!")
    }

}

