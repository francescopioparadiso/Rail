import SwiftUI
import SwiftData
import WidgetKit
import StoreKit


enum SearchType: String, CaseIterable {
    case number
    case stations
}
enum Daytime: String, CaseIterable {
    case morning
    case afternoon
    case night

    var label: String {
        switch self {
        case .morning: return NSLocalizedString("Morning", comment: "")
        case .afternoon: return NSLocalizedString("Afternoon", comment: "")
        case .night: return NSLocalizedString("Night", comment: "")
        }
    }
    var startHour: Int {
        switch self {
        case .morning: return 0
        case .afternoon: return 12
        case .night: return 18
        }
    }
    var endHour: Int {
        switch self {
        case .morning: return 12
        case .afternoon: return 18
        case .night: return 24
        }
    }
}
enum current_view: String, CaseIterable {
    case add_train
    case choose_train
    case choose_stops
    case choose_date
    
    var title: String {
        switch self {
        case .add_train:
            return NSLocalizedString("Add Train", comment: "")
        case .choose_train:
            return NSLocalizedString("Choose Train", comment: "")
        case .choose_stops:
            return NSLocalizedString("Choose Stops", comment: "")
        case .choose_date:
            return NSLocalizedString("Choose Date", comment: "")
        }
    }
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
            return NSLocalizedString("Searching solutions...", comment: "")
        case .failure:
            return NSLocalizedString("No solutions found", comment: "")
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
            return NSLocalizedString("Try checking the train number and your internet connection.", comment: "")
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
    var focus_initially: Bool = false
    // MARK: - variables
    // enviroment variables
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.requestReview) var requestReview
    @Environment(\.dismiss) private var dismiss
    
    // database variables
    @Environment(\.modelContext) private var modelContext
    @Query private var trains: [Train]
    @Query private var stops: [Stop]
    @Query private var favorites: [Favorite]
    
    // view state
    @State private var current_view: current_view = .add_train
    @State private var current_provider: current_provider = .trenitalia
    @State private var current_fetching: current_fetching = .idle
    
    // focus variables
    enum FocusField: Hashable { case number, departure, arrival }
    @FocusState private var focused_field: FocusField?
    private var is_focused: Bool { focused_field != nil }
    // measured height of the keyboard/back button so the suggestions pill can match it
    @State private var keyboard_button_height: CGFloat = 56
    
    // train search variables
    @State private var trains_fetched: [UUID: [String: Any]] = [:]
    @State private var trainID_selected: UUID? = nil
    @State private var stops_fetched: [[String: Any]] = []
    @State private var stops_selected: [[String: Any]] = []
    
    @State private var search_type: SearchType = .stations
    @State private var train_number: String = ""
    @State private var departure_station: String = ""
    @State private var arrival_station: String = ""
    @State private var departure_code: String = ""
    @State private var arrival_code: String = ""
    @State private var station_suggestions: [StationSuggestion] = []
    // true while a suggestion is being applied, so the text onChange doesn't clear the code
    @State private var is_selecting_station = false

    // stations search results
    @State private var solutions_fetched: [Solution] = []
    @State private var solutionID_selected: UUID? = nil
    @State private var selected_daytime: Daytime = .morning
    // suppress the picker's auto-scroll when we set the daytime programmatically
    @State private var suppress_daytime_scroll = false
    // bumped by the "Now" toolbar button to scroll to the next departure
    @State private var scroll_to_now_trigger = 0
    @State private var date_selected: Date = Date()
    @State private var show_date_picker_popover = false
    @State private var visible_solution_ids: Set<UUID> = []
    
    private var is_now_visible: Bool {
        let now = Date()
        guard let target = solutions_fetched.first(where: { $0.departureTime >= now }) else { return false }
        return visible_solution_ids.contains(target.id)
    }
    
    private var date_subtitle: String {
        let cal = Calendar.current
        let dateString = date_selected.formatted(.dateTime.day().month(.abbreviated))
        
        if cal.isDateInYesterday(date_selected) {
            return "Yesterday, \(dateString)"
        } else if cal.isDateInToday(date_selected) {
            return "Today, \(dateString)"
        } else if cal.isDateInTomorrow(date_selected) {
            return "Tomorrow, \(dateString)"
        } else {
            return dateString
        }
    }
    
    @AppStorage("autoSyncToCalendar") private var autoSyncToCalendar: Bool = true
    @AppStorage("calendarTitleFormat") private var titleFormat: String = "Train {number}"
    @AppStorage("selectedCalendarIdentifier") private var selectedCalendarIdentifier: String = ""
    @AppStorage("calendarTravelTime") private var travelTime: Double = 0

    // button properties
    private var back_button_icon: String {
        switch current_view {
        case .add_train:
            return "keyboard.chevron.compact.down"
        case .choose_train, .choose_stops, .choose_date:
            return "chevron.left"
        }
    }
    private var next_button_icon: String {
        switch current_view {
        case .add_train:
            if trainID_selected != nil {
                return "checkmark"
            } else {
                return "chevron.right"
            }
        case .choose_train:
            // stations: choosing a solution is the final step
            return search_type == .stations ? "checkmark" : "chevron.right"
        case .choose_stops:
            return "chevron.right"
        case .choose_date:
            return "checkmark"
        }
    }
    private var next_button_text: String {
        switch current_view {
        case .add_train:
            if trainID_selected != nil {
                return NSLocalizedString("Save", comment: "")
            } else {
                return NSLocalizedString("Next", comment: "")
            }
        case .choose_train:
            return search_type == .stations ? NSLocalizedString("Save", comment: "") : NSLocalizedString("Next", comment: "")
        case .choose_stops:
            return NSLocalizedString("Next", comment: "")
        case .choose_date:
            return NSLocalizedString("Save", comment: "")
        }
    }

    private var button_is_active: Bool {
        switch current_view {
        case .add_train:
            switch search_type {
            case .number:
                return train_number.count >= 2 || !stops_selected.isEmpty
            case .stations:
                return !departure_code.isEmpty && !arrival_code.isEmpty
            }

        case .choose_train:
            return search_type == .stations ? solutionID_selected != nil : trainID_selected != nil

        case .choose_stops:
            return stops_selected.count >= 2

        case .choose_date:
            return true
        }
    }
    
    private func close_button_action() -> Void {
        /// haptic feedback
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        
        /// change view
        dismiss()
        
        /// reset variables
        trains_fetched = [:]
        train_number = ""
        departure_station = ""
        arrival_station = ""
        departure_code = ""
        arrival_code = ""
        station_suggestions = []
        solutions_fetched = []
        solutionID_selected = nil
        trainID_selected = nil
        date_selected = Date()
    }
    private func back_button_action() -> Void {
        /// haptic feedback
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        
        switch current_view {
        case .add_train:
            /// reset variables
            focused_field = nil

        case .choose_train:
            /// update focus
            focused_field = nil
            
            /// change view
            current_view = .add_train
            
            /// reset variables
            trains_fetched.removeAll()
            trainID_selected = nil
            solutions_fetched.removeAll()
            solutionID_selected = nil

            /// fetching status
            current_fetching = .idle
            
        case .choose_stops:
            /// change view
            current_view = .choose_train
            
            /// reset variables
            stops_fetched.removeAll()
            stops_selected.removeAll()
            
        case .choose_date:
            /// change view
            current_view = .choose_stops
            
            /// reset variables
            date_selected = Date()
        }
    }
    private func next_button_action() -> Void {
        switch current_view {
        case .add_train:
            if trainID_selected == nil {
                /// haptic feedback
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                
                /// reset focus
                focused_field = nil

                /// change view
                current_view = .choose_train

                /// actions
                if search_type == .number {
                    Task { await fetch_trains() }
                } else {
                    Task { await fetch_solutions() }
                }
            } else {
                /// haptic feedback
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                
                /// actions
                save_train()
                
                /// change view
                dismiss()
            }
            
        case .choose_train:
            if search_type == .stations {
                /// haptic feedback
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()

                /// stations: a solution is fully specified, save it directly
                Task {
                    await save_solution()
                    dismiss()
                }
            } else {
                /// haptic feedback
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()

                /// change view
                current_view = .choose_stops

                /// actions
                save_stops()
            }

        case .choose_stops:
            /// haptic feedback
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            
            /// change view
            current_view = .choose_date
            
        case .choose_date:
            /// haptic feedback
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            
            /// actions
            save_train()
            
            /// change view
            dismiss()
        }
    }
    
    // MARK: - main view
    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                // MARK: - main content
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
                
                // MARK: - bottom bar
                bottom_bar()
            }
            .navigationTitle(current_view.title)
            .navigationBarTitleDisplayMode(.inline)
            .ignoresSafeArea(edges: is_focused ? [.top] : [.top, .bottom])
            .background(Color(UIColor.systemBackground))
            .toolbar(.hidden, for: .tabBar)
            .toolbar {
                // back or dismiss button
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        close_button_action()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
                
                // navigation title
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 0) {
                        Text(current_view.title)
                            .font(.headline)
                            .fontDesign(app_font_design)
                            .contentTransition(.numericText(value: Double(current_view.title.hashValue)))
                            .animation(.snappy, value: current_view.title)
                            
                        if current_view == .choose_train && search_type == .stations {
                            Text(date_subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fontDesign(app_font_design)
                                .contentTransition(.numericText(value: date_selected.timeIntervalSince1970))
                                .animation(.snappy, value: date_selected)
                        }
                    }
                    .padding(.horizontal, 16)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard current_view == .choose_train && search_type == .stations else { return }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        
                        show_date_picker_popover = true
                    }
                    .gesture(
                        DragGesture(minimumDistance: 10)
                            .onEnded { value in
                                guard current_view == .choose_train && search_type == .stations else { return }
                                
                                let direction = value.translation.width
                                guard abs(direction) > 20 else { return }
                                
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                
                                if direction < 0 {
                                    date_selected = Calendar.current.date(byAdding: .day, value: 1, to: date_selected) ?? date_selected
                                } else {
                                    date_selected = Calendar.current.date(byAdding: .day, value: -1, to: date_selected) ?? date_selected
                                }
                                Task { await fetch_solutions() }
                            }
                    )
                    .popover(isPresented: $show_date_picker_popover) {
                        DatePicker("", selection: $date_selected, displayedComponents: [.date])
                            .datePickerStyle(.graphical)
                            .padding()
                            .presentationDetents([.medium])
                            .onChange(of: date_selected) { _, _ in
                                show_date_picker_popover = false
                                Task { await fetch_solutions() }
                            }
                    }
                }

                // jump the solutions list to the next departure from now, or return to today
                if current_view == .choose_train && search_type == .stations && current_fetching == .success {
                    if Calendar.current.isDateInToday(date_selected) {
                        if !is_now_visible {
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Button("Now") {
                                    withAnimation {
                                        scroll_to_now_trigger += 1
                                    }
                                }
                                .fontDesign(app_font_design)
                            }
                        }
                    } else {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Today") {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                date_selected = Date()
                                Task { await fetch_solutions() }
                            }
                            .fontDesign(app_font_design)
                        }
                    }
                }
            }
        }
        .onAppear {
            if focus_initially {
                // Short delay ensures the sheet is presented before the keyboard tries to slide up
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    focused_field = search_type == .number ? .number : .departure
                }
            }
            Task { await fetch_favorites() }

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
        .onChange(of: train_number) { _, new_value in
            // only reset while editing on the add-train page (skip when a
            // favorite sets the number and jumps straight to choose_train)
            guard current_view == .add_train else { return }
            trains_fetched = [:]
            trainID_selected = nil
            stops_fetched = []
            stops_selected = []
            current_fetching = .idle
        }
        .onChange(of: search_type) { _, new_value in
            // move focus to the relevant field and clear stale suggestions
            station_suggestions = []
            focused_field = new_value == .number ? .number : .departure
        }
        .onChange(of: focused_field) { _, new_value in
            // refresh suggestions for whichever station field becomes active
            station_suggestions = []
            if new_value == .departure, departure_station.count >= 3 {
                Task { await fetch_stations(for: departure_station, field: .departure) }
            } else if new_value == .arrival, arrival_station.count >= 3 {
                Task { await fetch_stations(for: arrival_station, field: .arrival) }
            }
        }
        .onChange(of: departure_station) { _, new_value in
            // ignore the programmatic change made when applying a suggestion
            if is_selecting_station { is_selecting_station = false; return }
            departure_code = ""  // invalidate until a suggestion is picked
            Task { await fetch_stations(for: new_value, field: .departure) }
        }
        .onChange(of: arrival_station) { _, new_value in
            if is_selecting_station { is_selecting_station = false; return }
            arrival_code = ""  // invalidate until a suggestion is picked
            Task { await fetch_stations(for: new_value, field: .arrival) }
        }
    }
    
    // MARK: - views functions
    @ViewBuilder func add_train_view() -> some View {
        List {
            ZStack(alignment: .top) {
                if search_type == .number {
                    // number field
                    TextField("0", text: $train_number)
                        .font(.system(size: 80))
                        .fontDesign(app_font_design)
                        .fontWeight(.bold)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.center)
                        .focused($focused_field, equals: .number)
                        .padding(.top, 32)
                } else {
                    // stations fields
                    VStack(alignment: .leading, spacing: 20) {
                        TextField("Departure", text: $departure_station)
                            .focused($focused_field, equals: .departure)
                            .submitLabel(.next)
                            .onSubmit {
                                if let first = station_suggestions.first {
                                    select_station(first, field: .departure)
                                } else {
                                    focused_field = .arrival
                                }
                            }

                        TextField("Arrival", text: $arrival_station)
                            .focused($focused_field, equals: .arrival)
                            .submitLabel(.done)
                            .onSubmit {
                                if let first = station_suggestions.first {
                                    select_station(first, field: .arrival)
                                } else {
                                    focused_field = nil
                                }
                            }
                            
                        DatePicker("", selection: $date_selected)
                            .datePickerStyle(.compact)
                            .labelsHidden()
                            .font(.system(size: 22))
                    }
                    .font(.system(size: 28))
                    .fontDesign(app_font_design)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.leading)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                }
            }
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .frame(height: 200, alignment: .top)

            if !favorites.isEmpty {
                        // scrolling section header
                        HStack(spacing: 8) {
                            Image(systemName: "heart.fill")
                                .symbolColorRenderingMode(.gradient)
                            
                            Text("Favorites")
                        }
                        .font(.headline)
                        .fontWeight(.semibold)
                        .fontDesign(app_font_design)
                        .foregroundStyle(Color.secondary)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 32, leading: 24, bottom: 4, trailing: 16))
                        .opacity(is_focused ? 0.4 : 1.0)
                        .animation(.snappy, value: focused_field)

                        ForEach(favorites.sorted(by: { $0.index < $1.index })) { favorite in
                            Button {
                                select_favorite(favorite)
                            } label: {
                                favorite_card(favorite)
                            }
                            .buttonStyle(.plain)
                            // while typing: dim, disable tapping
                            .disabled(is_focused)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .opacity(is_focused ? 0.4 : 1.0)
                            .animation(.snappy, value: focused_field)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    delete_favorite(favorite)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                        .onMove(perform: move_favorites)

                        Text("You can reorder items by dragging and dropping them.")
                            .font(.footnote)
                            .fontDesign(app_font_design)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .padding(.top, 8)
                            .padding(.bottom, 32)
                            .opacity(is_focused ? 0.4 : 1.0)
                            .animation(.snappy, value: focused_field)
                    }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 96) }
        .safeAreaInset(edge: .top) {
            Picker("Search Type", selection: $search_type) {
                Text("Stations").tag(SearchType.stations)
                Text("Train number").tag(SearchType.number)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 48)
            .padding(.top, 72)
            .padding(.bottom, 36)
            .background(
                Rectangle()
                    .fill(.regularMaterial)
                    .ignoresSafeArea(.all, edges: .top)
                    .mask(
                        LinearGradient(
                            stops: [
                                .init(color: .black, location: 0),
                                .init(color: .black, location: 0.75),
                                .init(color: .black.opacity(0.85), location: 0.8),
                                .init(color: .black.opacity(0.6), location: 0.85),
                                .init(color: .black.opacity(0.3), location: 0.9),
                                .init(color: .clear, location: 1)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
        }
    }

    // favorite train card — same design as AddFavoriteView
    @ViewBuilder func favorite_card(_ favorite: Favorite) -> some View {
        VStack(spacing: 16) {
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
                    if let time = favorite.stop_ref_times.first {
                        Text(time.formatted(Date.FormatStyle.dateTime.hour().minute()))
                            .monospacedDigit()
                    }
                }
                HStack {
                    Text(favorite.stop_names.last ?? "")
                    Spacer()
                    if let time = favorite.stop_ref_times.last {
                        Text(time.formatted(Date.FormatStyle.dateTime.hour().minute()))
                            .monospacedDigit()
                    }
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
                .stroke(style: StrokeStyle(lineWidth: 1, dash: [5]))
                .foregroundColor(Color.primary.opacity(0.5))
        )
    }

    // MARK: - bottom bar
    @ViewBuilder func bottom_bar() -> some View {
        Group {
            if current_view == .add_train && search_type == .stations,
               let field = focused_field, field != .number {
                station_suggestion_bar(field: field)
            } else {
                default_buttons()
            }
        }
        .padding(.bottom, is_focused ? 8 : 16)
        .padding(.horizontal)
        .animation(.snappy, value: focused_field)
        .animation(.snappy, value: search_type)
    }

    @ViewBuilder func default_buttons() -> some View {
        HStack(spacing: 8) {
            // back button
            if !(!is_focused && current_view == .add_train) {
                back_button()
            }

            // next button
            next_button()
        }
    }

    @ViewBuilder func back_button() -> some View {
        Button {
            back_button_action()
        } label: {
            Image(systemName: back_button_icon)
                .padding(.horizontal, is_focused ? 16 : 24)
                .padding(.vertical, is_focused ? 16 : 24)
                .contentTransition(.symbolEffect(.replace.downUp.wholeSymbol, options: .nonRepeating))
        }
        .font(.title3)
        .fontWeight(.medium)
        .fontDesign(app_font_design)
        .buttonStyle(.glassProminent)
        .foregroundStyle(Color.accentColor)
        .tint(Color.accentColor.opacity(0.15))
        .transition(.asymmetric(
            insertion: .scale(scale: 0.8).combined(with: .opacity),
            removal: .scale(scale: 0.8).combined(with: .opacity)
        ))
    }

    @ViewBuilder func next_button() -> some View {
        Button {
            if button_is_active {
                next_button_action()
            }
        } label: {
            HStack {
                Text(next_button_text)
                    .contentTransition(.numericText(value: Double(next_button_text.hashValue)))
                    .animation(.snappy, value: next_button_text)

                Image(systemName: next_button_icon)
                    .symbolEffect(.wiggle.byLayer, options: .repeat(.periodic(delay: 5.0)))
                    .contentTransition(.symbolEffect(.replace.downUp.wholeSymbol, options: .nonRepeating))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, is_focused ? 16 : 24)
        }
        .font(.title3)
        .fontWeight(.medium)
        .fontDesign(app_font_design)
        .buttonStyle(.glassProminent)
        .foregroundStyle(button_is_active ? Color.accentColor : Color.primary)
        .tint(button_is_active ? Color.accentColor.opacity(0.15) : colorScheme == .dark ? Color.black.opacity(0.1) : Color.clear)
    }

    // floating bar shown while typing a station: a keyboard/back pill on the
    // left and a horizontally scrolling pill of station suggestions.
    @ViewBuilder func station_suggestion_bar(field: FocusField) -> some View {
        HStack(spacing: 8) {
            // departure → dismiss keyboard, arrival → back to departure
            // same style/size as the train-number back button
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                focused_field = field == .departure ? nil : .departure
            } label: {
                Image(systemName: field == .departure ? "keyboard.chevron.compact.down" : "chevron.left")
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                    .contentTransition(.symbolEffect(.replace.downUp.wholeSymbol, options: .nonRepeating))
            }
            .font(.title3)
            .fontWeight(.medium)
            .fontDesign(app_font_design)
            .buttonStyle(.glassProminent)
            .foregroundStyle(Color.accentColor)
            .tint(Color.accentColor.opacity(0.15))
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { keyboard_button_height = $0 }

            if station_suggestions.isEmpty {
                Spacer(minLength: 0)
            } else {
                suggestions_pill(field: field)
            }
        }
    }

    @ViewBuilder func suggestions_pill(field: FocusField) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(station_suggestions, id: \.self) { station in
                    station_chip(station, field: field)
                }
            }
            .padding(.horizontal, 12)
            .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity)
        .frame(height: keyboard_button_height)
        // fade the chips at the edges, masking before the glass keeps the pill solid
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.12),
                    .init(color: .black, location: 0.88),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .glassEffect(.regular)
    }

    @ViewBuilder func station_chip(_ station: StationSuggestion, field: FocusField) -> some View {
        Button {
            select_station(station, field: field)
        } label: {
            Text(station.name)
                .font(.subheadline).fontWeight(.medium)
                .fontDesign(app_font_design)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(height: 32)
                .padding(.vertical, 6).padding(.horizontal, 16)
                .background(.thinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
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
            .padding(.bottom, 80)
            
        case .success:
            if search_type == .stations {
                choose_solution_view()
            } else {
                ScrollView {
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
                                                .monospacedDigit()
                                        }
                                        
                                        HStack {
                                            Text(lastStop_name)
                                            Spacer()
                                            Text(lastStop_refTime.formatted(Date.FormatStyle.dateTime.hour().minute()))
                                                .monospacedDigit()
                                        }
                                    }
                                    .font(.subheadline)
                                }
                                .fontDesign(app_font_design)
                                .foregroundStyle(Color.primary)
                                .padding()
                                .background(
                                    RoundedRectangle(cornerRadius: 24)
                                        .stroke(style: trainID_selected == id ? StrokeStyle(lineWidth: 2) : StrokeStyle(lineWidth: 1, dash: [5]))
                                        .foregroundColor(trainID_selected == id ? Color.accentColor : Color.primary.opacity(0.5))
                                )
                            }
                            .padding()
                        }
                    }
                    
                    Color.clear
                        .frame(height: 80)
                }
                .contentMargins(.top, 72, for: .scrollContent)
                .contentMargins(.bottom, 104)
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

    // MARK: - stations solutions list
    @ViewBuilder func choose_solution_view() -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 48) {
                        ForEach(solutions_fetched) { solution in
                            let isSelected = solutionID_selected == solution.id

                            // one dashed card per train; the connection assistant sits
                            // between cards (outside the borders). Larger spacing between
                            // solutions keeps multi-train journeys visually grouped.
                            VStack(spacing: 8) {
                                ForEach(Array(solution.segments.enumerated()), id: \.offset) { index, segment in
                                    Button {
                                        solutionID_selected = isSelected ? nil : solution.id
                                    } label: {
                                        if segment.isBus {
                                            // bus-substitution leg → blue assistant with a bus icon
                                            bus_segment_view(segment)
                                                .frame(maxWidth: .infinity)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 24)
                                                        .fill(isSelected ? Color.blue.opacity(0.12) : Color.clear)
                                                )
                                        } else {
                                            solution_segment_view(segment)
                                                .fontDesign(app_font_design)
                                                .foregroundStyle(Color.primary)
                                                .padding()
                                                .frame(maxWidth: .infinity)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 24)
                                                        .stroke(style: isSelected ? StrokeStyle(lineWidth: 2) : StrokeStyle(lineWidth: 1, dash: [5]))
                                                        .foregroundColor(isSelected ? Color.accentColor : Color.primary.opacity(0.5))
                                                )
                                        }
                                    }

                                    if index < solution.segments.count - 1 {
                                        connection_view(from: segment, to: solution.segments[index + 1])
                                    }
                                }
                            }
                            .id(solution.id)
                            .onAppear {
                                withAnimation {
                                    _ = visible_solution_ids.insert(solution.id)
                                }
                            }
                            .onDisappear {
                                withAnimation {
                                    _ = visible_solution_ids.remove(solution.id)
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)

                    // bottom clearance so the back/save buttons don't overlay the last solution
                    Color.clear
                        .frame(height: 120)
                }
                .scrollIndicators(.hidden)
                .safeAreaInset(edge: .top) {
                    // daytime quick-nav: scrolls to the first solution in the interval
                    Picker("Daytime", selection: $selected_daytime) {
                        ForEach(Daytime.allCases, id: \.self) { daytime in
                            Text(daytime.label).tag(daytime)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.top, 80)
                    .padding(.bottom, 40)
                    .background(
                        LinearGradient(
                            stops: [
                                .init(color: Color(UIColor.systemBackground), location: 0),
                                .init(color: Color(UIColor.systemBackground), location: 0.75),
                                .init(color: Color(UIColor.systemBackground).opacity(0), location: 1)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .onChange(of: selected_daytime) { _, daytime in
                        // ignore the programmatic set we do when opening the list
                        if suppress_daytime_scroll { suppress_daytime_scroll = false; return }
                        guard let target = solutions_fetched.first(where: {
                            let hour = Calendar.current.component(.hour, from: $0.departureTime)
                            return hour >= daytime.startHour && hour < daytime.endHour
                        }) else { return }
                        withAnimation { proxy.scrollTo(target.id, anchor: .top) }
                    }
                }
            .onAppear { scroll_to_next_solution(proxy: proxy, animated: false) }
            .onChange(of: scroll_to_now_trigger) { _, _ in scroll_to_next_solution(proxy: proxy, animated: true) }
        }
    }

    // on open, jump straight to the next departure from now so the user can catch it
    private func scroll_to_next_solution(proxy: ScrollViewProxy, animated: Bool = false) {
        let now = Date()
        guard let target = solutions_fetched.first(where: { $0.departureTime >= now }) else { return }

        // reflect the next train's interval in the picker without triggering its scroll
        let hour = Calendar.current.component(.hour, from: target.departureTime)
        if let daytime = Daytime.allCases.first(where: { hour >= $0.startHour && hour < $0.endHour }) {
            suppress_daytime_scroll = true
            selected_daytime = daytime
        }

        DispatchQueue.main.async {
            if animated {
                withAnimation { proxy.scrollTo(target.id, anchor: .top) }
            } else {
                proxy.scrollTo(target.id, anchor: .top)
            }
        }
    }

    @ViewBuilder func solution_segment_view(_ segment: SolutionSegment) -> some View {
        VStack(spacing: 16) {
            // logo + number
            HStack {
                Image(segment.logo)
                    .resizable()
                    .scaledToFit()
                    .frame(height: UIFont.preferredFont(forTextStyle: .title3).lineHeight * 0.8)

                Text(segment.number)
                    .font(.title3)
                    .fontWeight(.semibold)

                Spacer()
            }

            // origin/destination + times
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(segment.origin)
                    Spacer()
                    Text(segment.departureTime.formatted(Date.FormatStyle.dateTime.hour().minute()))
                        .monospacedDigit()
                }
                HStack {
                    Text(segment.destination)
                    Spacer()
                    Text(segment.arrivalTime.formatted(Date.FormatStyle.dateTime.hour().minute()))
                        .monospacedDigit()
                }
            }
            .font(.subheadline)
        }
    }

    // bus-substitution leg, styled like the connection assistant but blue with a bus icon
    @ViewBuilder func bus_segment_view(_ segment: SolutionSegment) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Rectangle()
                .fill(Color.blue.opacity(0.3))
                .frame(width: 3)
                .cornerRadius(1.5)

            Image(systemName: "bus.fill")
                .font(.title3)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text("\(NSLocalizedString("Bus", comment: "")) \(segment.number)")
                    .font(.footnote).fontWeight(.semibold)

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(segment.origin)
                        Spacer()
                        Text(segment.departureTime.formatted(Date.FormatStyle.dateTime.hour().minute()))
                            .monospacedDigit()
                    }
                    HStack {
                        Text(segment.destination)
                        Spacer()
                        Text(segment.arrivalTime.formatted(Date.FormatStyle.dateTime.hour().minute()))
                            .monospacedDigit()
                    }
                }
                .font(.caption)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 8).padding(.horizontal)
        .fontDesign(app_font_design)
        .foregroundColor(.blue)
    }

    @ViewBuilder func connection_view(from: SolutionSegment, to: SolutionSegment) -> some View {
        let totalMinutes = max(0, Int(to.departureTime.timeIntervalSince(from.arrivalTime)) / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        let durationString = hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"

        ConnectionIntervalView(
            durationString: durationString,
            totalMinutes: totalMinutes,
            connectionStatus: ConnectionStatus(minutes: totalMinutes),
            station: from.destination,
            weather: nil,
            index: 0,
            total: 1,
            manualRefreshCounter: 0
        )
    }
    
    @ViewBuilder func choose_stops_view() -> some View {
        ZStack(alignment: .bottom) {
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
                                .monospacedDigit()
                        }
                        .fontDesign(app_font_design)
                        .foregroundStyle(Color.primary)
                        .padding(4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowSeparator(index == 0 ? .hidden : .visible, edges: .top)
                }
                
                Color.clear
                    .frame(height: 80)
                    .listRowSeparator(.hidden)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollIndicators(.hidden)
            .contentMargins(.horizontal, 8, for: .scrollContent)
            .contentMargins(.top, 72, for: .scrollContent)
            .padding(.bottom, 8)
        }
        .background(Color(UIColor.systemBackground))
        .ignoresSafeArea(edges: .bottom)
        .toolbar(.hidden, for: .tabBar)
    }
    
    @ViewBuilder func choose_date_view() -> some View {
        ScrollView {
            DatePicker("", selection: $date_selected, in: Date()..., displayedComponents: [.date])
                .datePickerStyle(GraphicalDatePickerStyle())
            
            Color.clear
                .frame(height: 80)
        }
        .contentMargins(.top, 72, for: .scrollContent)
        .padding(.horizontal, 8)
    }
    
    // MARK: - fetching functions
    private func fetch_stations(for query: String, field: FocusField) async {
        guard query.count >= 3 else {
            station_suggestions = []
            return
        }
        let results = await TrenitaliaAPI().station_autocomplete(name: query)
        await MainActor.run {
            // discard results that arrived after the focus or text changed
            guard focused_field == field else { return }
            let current = field == .departure ? departure_station : arrival_station
            guard current == query else { return }
            station_suggestions = results
        }
    }

    private func select_station(_ station: StationSuggestion, field: FocusField) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        station_suggestions = []
        is_selecting_station = true
        if field == .departure {
            departure_station = station.name
            departure_code = station.code
            focused_field = .arrival
        } else {
            arrival_station = station.name
            arrival_code = station.code
            focused_field = nil
        }
    }

    private func fetch_solutions() async {
        current_fetching = .fetching

        let results = await TrenitaliaAPI().train_solutions(
            departureLocationId: departure_code,
            arrivalLocationId: arrival_code,
            departureTime: date_selected
        )

        await MainActor.run {
            solutions_fetched = results
            current_fetching = results.isEmpty ? .failure : .success
        }
    }

    // saves the selected solution: each leg becomes its own train, so connected
    // journeys render with the connection manager just like in TodayView.
    private func save_solution() async {
        guard let solution = solutions_fetched.first(where: { $0.id == solutionID_selected }) else { return }

        for segment in solution.segments {
            let identifiers = await TrenitaliaAPI().train_list(number: segment.number, code: segment.stationCode)

            let segmentDay = Calendar.current.startOfDay(for: segment.departureTime)
            var targetIdentifier = identifiers.first
            var dayOffset = 0
            
            if let exactId = identifiers.first(where: { id in
                guard let tsString = id.split(separator: "/").last, let ms = Double(tsString) else { return false }
                return Calendar.current.isDate(Date(timeIntervalSince1970: ms / 1000), inSameDayAs: segmentDay)
            }) {
                targetIdentifier = exactId
            } else if let firstId = identifiers.first {
                if let tsString = firstId.split(separator: "/").last, let ms = Double(tsString) {
                    let firstIdDay = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: ms / 1000))
                    dayOffset = Calendar.current.dateComponents([.day], from: firstIdDay, to: segmentDay).day ?? 0
                }
            }

            guard let identifier = targetIdentifier,
                  let info = await TrenitaliaAPI().info(identifier: identifier, should_fetch_weather: false) else { continue }

            await MainActor.run {
                save_segment(info: info, fromStation: segment.origin, toStation: segment.destination, dayOffset: dayOffset)
            }
        }

        await MainActor.run {
            try? modelContext.save()
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    private func save_segment(info: [String: Any], fromStation: String, toStation: String, dayOffset: Int = 0) {
        let id = UUID()
        
        func offsetDate(_ date: Date) -> Date {
            if dayOffset == 0 { return date }
            return Calendar.current.date(byAdding: .day, value: dayOffset, to: date) ?? date
        }

        let train = Train(
            id: id,
            logo: info["logo"] as? String ?? "",
            number: info["number"] as? String ?? "",
            identifier: info["identifier"] as? String ?? "",
            provider: info["provider"] as? String ?? "",
            last_update_time: offsetDate(info["last_update_time"] as? Date ?? Date()),
            delay: dayOffset != 0 ? 0 : (info["delay"] as? Int ?? 0),
            direction: info["direction"] as? String ?? "",
            issue: info["issue"] as? String ?? ""
        )
        modelContext.insert(train)

        let stops = info["stops"] as? [[String: Any]] ?? []
        let names = stops.map { $0["name"] as? String ?? "" }
        let fromIdx = names.firstIndex(of: fromStation)
        let toIdx = names.firstIndex(of: toStation)

        for (i, stop) in stops.enumerated() {
            // mark only the stops on the ridden segment (origin → destination) as selected
            let is_selected: Bool = {
                guard let f = fromIdx, let t = toIdx else { return false }
                return i >= f && i <= t
            }()

            let stop_to_add = Stop(
                id: id,
                name: stop["name"] as? String ?? "",
                platform: stop["platform"] as? String ?? "",
                weather: stop["weather"] as? String ?? "",
                is_selected: is_selected,
                status: dayOffset != 0 ? 0 : (stop["status"] as? Int ?? 0),
                is_completed: dayOffset != 0 ? false : (stop["is_completed"] as? Bool ?? false),
                is_in_station: dayOffset != 0 ? false : (stop["is_in_station"] as? Bool ?? false),
                dep_delay: dayOffset != 0 ? 0 : (stop["dep_delay"] as? Int ?? 0),
                arr_delay: dayOffset != 0 ? 0 : (stop["arr_delay"] as? Int ?? 0),
                dep_time_id: offsetDate(stop["dep_time_id"] as? Date ?? .distantPast),
                arr_time_id: offsetDate(stop["arr_time_id"] as? Date ?? .distantPast),
                dep_time_eff: dayOffset != 0 ? offsetDate(stop["dep_time_id"] as? Date ?? .distantPast) : offsetDate(stop["dep_time_eff"] as? Date ?? .distantPast),
                arr_time_eff: dayOffset != 0 ? offsetDate(stop["arr_time_id"] as? Date ?? .distantPast) : offsetDate(stop["arr_time_eff"] as? Date ?? .distantPast),
                ref_time: offsetDate(stop["ref_time"] as? Date ?? .distantPast)
            )
            modelContext.insert(stop_to_add)
        }
    }

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
            issue: issue
        )
        modelContext.insert(train_to_add)
        
        var addedStops: [Stop] = []

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
            addedStops.append(stop_to_add)
        }
        
        try? modelContext.save()
        
        // MARK: - calendar sync
        if autoSyncToCalendar {
            Task {
                await CalendarManager.shared.syncTrainEvent(
                    train: train_to_add,
                    stops: addedStops,
                    seats: [], // No seats yet when adding a train
                    titleFormat: titleFormat,
                    calendarIdentifier: selectedCalendarIdentifier,
                    travelTime: travelTime
                )
            }
        }
        
        WidgetCenter.shared.reloadAllTimelines()
        
        print("\n ✅ Train and stops saved successfully!")
    }
    
    private func fetch_favorites() async {
        await withTaskGroup(of: (UUID, [String: Any]?).self) { group in
            for favorite in favorites {
                let identifier: String = {
                    if favorite.provider == "trenitalia" {
                        let today_timestamp = Int(Date().timeIntervalSince1970) * 1000
                        return "\(favorite.identifier)/\(today_timestamp)"
                    } else {
                        return favorite.identifier
                    }
                }()
                
                group.addTask {
                    let train_info = await {
                        if favorite.provider == "trenitalia" {
                            return await TrenitaliaAPI().info(identifier: identifier, should_fetch_weather: false)
                        } else if favorite.provider == "italo" {
                            return await ItaloAPI().info(identifier: identifier, should_fetch_weather: false)
                        } else {
                            return nil
                        }
                    }()
                    return (favorite.id, train_info)
                }
            }
            
            for await (id, info) in group {
                await MainActor.run {
                    trains_fetched[id] = info
                }
            }
        }
        
        print("🔄 Favorites fetched successfully!")
    }
    
    private func delete_favorite(at offsets: IndexSet) {
        let items = offsets.map { favorites[$0] }
        for favorite in items {
            modelContext.delete(favorite)
        }
    }

    private func delete_favorite(_ favorite: Favorite) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        modelContext.delete(favorite)

        // re-index the remaining favorites to keep the order contiguous
        let remaining = favorites.filter { $0.id != favorite.id }.sorted(by: { $0.index < $1.index })
        for (i, fav) in remaining.enumerated() { fav.index = i }

        try? modelContext.save()
    }

    // tap a favorite → fill the appropriate fields and automatically search
    private func select_favorite(_ favorite: Favorite) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        focused_field = nil
        
        if search_type == .number {
            train_number = favorite.number
            current_view = .choose_train
            Task { await fetch_trains() }
        } else {
            departure_station = favorite.stop_names.first ?? ""
            arrival_station = favorite.stop_names.last ?? ""
            current_view = .choose_train
            
            Task {
                current_fetching = .fetching
                
                let dep_suggs = await TrenitaliaAPI().station_autocomplete(name: departure_station)
                if let dep = dep_suggs.first {
                    departure_code = dep.code
                }
                
                let arr_suggs = await TrenitaliaAPI().station_autocomplete(name: arrival_station)
                if let arr = arr_suggs.first {
                    arrival_code = arr.code
                }
                
                await fetch_solutions()
            }
        }
    }

    private func move_favorites(from source: IndexSet, to destination: Int) {
        var ordered = favorites.sorted(by: { $0.index < $1.index })
        ordered.move(fromOffsets: source, toOffset: destination)
        for (i, favorite) in ordered.enumerated() {
            favorite.index = i
        }
        try? modelContext.save()
    }
}

// MARK: - previews
extension AddTrainView {
    init(
        previewView: current_view,
        stopsFetched: [[String: Any]] = [],
        stopsSelected: [[String: Any]] = [],
    ) {
        self._current_view = State(initialValue: previewView)
        self._stops_fetched = State(initialValue: stopsFetched)
        self._stops_selected = State(initialValue: stopsSelected)
    }

    // preview helper for the "Choose Train" step (number search → trains, stations search → solutions)
    init(
        previewView: current_view,
        searchType: SearchType,
        fetching: current_fetching,
        trainsFetched: [UUID: [String: Any]] = [:],
        solutionsFetched: [Solution] = []
    ) {
        self._current_view = State(initialValue: previewView)
        self._search_type = State(initialValue: searchType)
        self._current_fetching = State(initialValue: fetching)
        self._trains_fetched = State(initialValue: trainsFetched)
        self._solutions_fetched = State(initialValue: solutionsFetched)
    }
}

#Preview("Add Train View") {
    // memory container
    let container = try! ModelContainer(for: Schema([Train.self, Stop.self]), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    
    // view
    return Color(uiColor: .systemBackground)
        .sheet(isPresented: .constant(true)) {
            AddTrainView(previewView: .add_train)
                .modelContainer(container)
        }
}

#Preview("Add Train View - with favorites") {
    // memory containers
    let schema = Schema([Train.self, Stop.self, Favorite.self])
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
    return Color(uiColor: .systemBackground)
        .sheet(isPresented: .constant(true)) {
            AddTrainView(previewView: .add_train)
                .modelContainer(container)
        }
}

#Preview("Choose Stops View") {
    // memory container
    let schema = Schema([Train.self, Stop.self])
    let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    
    // mock data
    let start = Date()
    let mockStops: [[String: Any]] = [
        ["name": "Torino Porta Nuova", "ref_time": start],
        ["name": "Torino Porta Susa", "ref_time": start.addingTimeInterval(600)],      // +10 min
        ["name": "Milano Centrale", "ref_time": start.addingTimeInterval(3600)],        // +1 hour
        ["name": "Reggio Emilia AV", "ref_time": start.addingTimeInterval(5400)],       // +1.5 hours
        ["name": "Bologna Centrale", "ref_time": start.addingTimeInterval(7200)],       // +2 hours
        ["name": "Firenze S.M.N.", "ref_time": start.addingTimeInterval(10800)],       // +3 hours
        ["name": "Roma Tiburtina", "ref_time": start.addingTimeInterval(16200)],        // +4.5 hours
        ["name": "Roma Termini", "ref_time": start.addingTimeInterval(17100)],          // +4h 45m
        ["name": "Napoli Afragola", "ref_time": start.addingTimeInterval(20700)],       // +5h 45m
        ["name": "Napoli Centrale", "ref_time": start.addingTimeInterval(21600)],       // +6 hours
        ["name": "Salerno", "ref_time": start.addingTimeInterval(23400)]                // +6.5 hours
    ]
    
    do {
        let container = try ModelContainer(for: schema, configurations: modelConfiguration)
        
        // view
        return Color(uiColor: .systemBackground)
            .sheet(isPresented: .constant(true)) {
                AddTrainView(
                    previewView: .choose_stops,
                    stopsFetched: mockStops,
                    stopsSelected: [mockStops[0], mockStops[1]]
                )
                .modelContainer(container)
            }
        
    } catch {
        return ContentUnavailableView("SwiftData Error", systemImage: "xmark.octagon", description: Text(error.localizedDescription))
    }
}

#Preview("Choose Train - number search") {
    // memory container
    let container = try! ModelContainer(for: Schema([Train.self, Stop.self, Favorite.self]), configurations: ModelConfiguration(isStoredInMemoryOnly: true))

    let start = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date())!

    // mock trains for number "757"
    let trainsFetched: [UUID: [String: Any]] = [
        UUID(): [
            "number": "757",
            "logo": "FR",
            "stops": [
                ["name": "Milano Centrale", "ref_time": start],
                ["name": "Roma Termini", "ref_time": start.addingTimeInterval(3 * 3600)]
            ]
        ],
        UUID(): [
            "number": "757",
            "logo": "IC",
            "stops": [
                ["name": "Torino Porta Nuova", "ref_time": start.addingTimeInterval(1800)],
                ["name": "Napoli Centrale", "ref_time": start.addingTimeInterval(6 * 3600)]
            ]
        ]
    ]

    return Color(uiColor: .systemBackground)
        .sheet(isPresented: .constant(true)) {
            AddTrainView(
                previewView: .choose_train,
                searchType: .number,
                fetching: .success,
                trainsFetched: trainsFetched
            )
            .modelContainer(container)
        }
}

#Preview("Choose Train - stations search") {
    // memory container
    let container = try! ModelContainer(for: Schema([Train.self, Stop.self, Favorite.self]), configurations: ModelConfiguration(isStoredInMemoryOnly: true))

    let start = Calendar.current.date(bySettingHour: 8, minute: 30, second: 0, of: Date())!

    // mock solutions for Milano Centrale → Roma Termini
    let solutionsFetched: [Solution] = [
        // direct
        Solution(segments: [
            SolutionSegment(
                origin: "Milano Centrale", destination: "Roma Termini",
                departureTime: start, arrivalTime: start.addingTimeInterval(3 * 3600),
                logo: "FR", number: "9612", stationCode: "S01700", isBus: false
            )
        ]),
        // with a connection in Bologna
        Solution(segments: [
            SolutionSegment(
                origin: "Milano Centrale", destination: "Bologna Centrale",
                departureTime: start.addingTimeInterval(900), arrivalTime: start.addingTimeInterval(900 + 64 * 60),
                logo: "FR", number: "9613", stationCode: "S01700", isBus: false
            ),
            SolutionSegment(
                origin: "Bologna Centrale", destination: "Roma Termini",
                departureTime: start.addingTimeInterval(900 + 90 * 60), arrivalTime: start.addingTimeInterval(900 + 90 * 60 + 125 * 60),
                logo: "IC", number: "605", stationCode: "S05043", isBus: false
            )
        ]),
        // train + replacement bus
        Solution(segments: [
            SolutionSegment(
                origin: "Milano Centrale", destination: "Firenze S.M.N.",
                departureTime: start.addingTimeInterval(1800), arrivalTime: start.addingTimeInterval(1800 + 110 * 60),
                logo: "FR", number: "9615", stationCode: "S01700", isBus: false
            ),
            SolutionSegment(
                origin: "Firenze S.M.N.", destination: "Roma Termini",
                departureTime: start.addingTimeInterval(1800 + 140 * 60), arrivalTime: start.addingTimeInterval(1800 + 140 * 60 + 95 * 60),
                logo: "BU", number: "FI451", stationCode: "S06421", isBus: true
            )
        ])
    ]

    return Color(uiColor: .systemBackground)
        .sheet(isPresented: .constant(true)) {
            AddTrainView(
                previewView: .choose_train,
                searchType: .stations,
                fetching: .success,
                solutionsFetched: solutionsFetched
            )
            .modelContainer(container)
        }
}
