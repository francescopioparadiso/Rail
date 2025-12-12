import SwiftUI

import PhotosUI
import Vision
import CoreImage.CIFilterBuiltins

enum adding_row_focus {
    case carriage
    case seat
    case name
}

enum processing_steps {
    case empty
    case saved
    case error
}

struct SeatsView: View {
    @Environment(\.modelContext) private var modelContext
    
    let train: Train
    let stops: [Stop]
    @Binding var seats_sheet: Bool
    
    @State private var newCarriage: String = ""
    @State private var newSeat: String = ""
    @State private var newName: String = ""
    @State private var newTicketPayload: String = ""
    @State private var newTicketSymbology: String = ""
    
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var seatToView: String?
    
    @State private var show_adding_row: Bool = false
    @FocusState private var adding_row_focused_field: adding_row_focus?
    @State private var processing_steps: processing_steps = .empty
    
    var body: some View {
        let sortedSeats = train.seats.sorted { seat1, seat2 in
            let parts1 = seat1.split(separator: "-")
            let parts2 = seat2.split(separator: "-")
            
            guard parts1.count >= 2 && parts2.count >= 2 else {
                return seat1.localizedStandardCompare(seat2) == .orderedAscending
            }
            
            let carriage1 = Int(parts1[0]) ?? 0
            let carriage2 = Int(parts2[0]) ?? 0
            
            if carriage1 != carriage2 {
                return carriage1 < carriage2
            }
            
            let seatNum1 = Int(parts1[1].filter { $0.isNumber }) ?? 0
            let seatNum2 = Int(parts2[1].filter { $0.isNumber }) ?? 0
            
            if seatNum1 != seatNum2 {
                return seatNum1 < seatNum2
            }
            
            let seatLetter1 = parts1[1].filter { $0.isLetter }
            let seatLetter2 = parts2[1].filter { $0.isLetter }
            
            if seatLetter1 != seatLetter2 {
                return seatLetter1 < seatLetter2
            }
            
            let name1 = parts1.count > 2 ? parts1.dropFirst(2).joined(separator: "-") : ""
            let name2 = parts2.count > 2 ? parts2.dropFirst(2).joined(separator: "-") : ""
            
            return name1 < name2
        }
        
        NavigationStack {
            List {
                // empty view
                if !show_adding_row && sortedSeats.isEmpty {
                    ContentUnavailableView("No seats added",
                                           systemImage: "airplaneseat",
                                           description: Text("Add a new seat by tapping the above button."))
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .foregroundColor(Color.secondary)
                    .fontDesign(appFontDesign)
                }
                
                // add seat row
                if show_adding_row {
                    HStack {
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("Francesco", text: $newName)
                                .font(.headline)
                                .keyboardType(.default)
                                .focused($adding_row_focused_field, equals: .name)
                                .onTapGesture {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                }
                                .onSubmit {
                                    adding_row_focused_field = .carriage
                                }
                                .onChange(of: newSeat) { _, newValue in
                                    if newValue.count >= 15 {
                                        newSeat = String(newValue.prefix(15))
                                    }
                                }
                            
                            HStack {
                                HStack(spacing: 8) {
                                    Image(systemName: "train.side.rear.car")
                                    TextField("22", text: $newCarriage)
                                        .keyboardType(.numbersAndPunctuation)
                                        .focused($adding_row_focused_field, equals: .carriage)
                                        .onTapGesture {
                                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        }
                                        .onSubmit {
                                            adding_row_focused_field = .seat
                                        }
                                        .onChange(of: newCarriage) { _, newValue in
                                            if newValue.count >= 2 {
                                                adding_row_focused_field = .seat
                                                newCarriage = String(newValue.prefix(2))
                                            }
                                        }
                                    Spacer(minLength: 0)
                                }
                                .frame(maxWidth: 64)
                                
                                HStack(spacing: 8) {
                                    Image(systemName: "carseat.left.fill")
                                    TextField("15A", text: $newSeat)
                                        .keyboardType(.numbersAndPunctuation)
                                        .focused($adding_row_focused_field, equals: .seat)
                                        .onTapGesture {
                                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        }
                                        .onChange(of: newSeat) { _, newValue in
                                            if newValue.count >= 3 {
                                                newSeat = String(newValue.prefix(3))
                                            }
                                        }
                                }
                            }
                            .font(.body)
                            .fontDesign(appFontDesign)
                        }
                        
                        Spacer()
                        
                        let icon = {
                            switch processing_steps {
                            case .empty:
                                return "qrcode.viewfinder"
                            case .saved:
                                return "checkmark.circle.fill"
                            case .error:
                                return "xmark.circle.fill"
                            }
                        }()
                        
                        let iconColor = {
                            switch processing_steps {
                            case .empty:
                                return Color.secondary
                            case .saved:
                                return Color.green
                            case .error:
                                return Color.red
                            }
                        }()
                        
                        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                            Image(systemName: icon)
                                .font(.title)
                                .foregroundStyle(iconColor)
                                .contentTransition(.symbolEffect(.replace.magic(fallback: .downUp.byLayer), options: .nonRepeating))
                        }
                        .onChange(of: selectedPhotoItem) { _, newItem in
                            processPhoto(item: newItem)
                        }
                    }
                    .foregroundStyle(Color.secondary)
                }
                
                // existing rows
                ForEach(sortedSeats, id: \.self) { seat in
                    let components = seat.split(separator: "-")
                    let carriageString = components[0]
                    let seatString = components[1]
                    let nameString = components[2]
                    let ticketString = components[3]
                    
                    HStack {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(nameString)
                                .font(.headline)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            
                            if carriageString != "NaN" && seatString != "NaN" {
                                HStack {
                                    HStack(spacing: 8) {
                                        Image(systemName: "train.side.rear.car")
                                        Text(carriageString)
                                        Spacer(minLength: 0)
                                    }
                                    .frame(maxWidth: 64)
                                    
                                    HStack(spacing: 8) {
                                        Image(systemName: "carseat.left.fill")
                                        Text(seatString)
                                    }
                                }
                                .font(.body)
                            }
                        }
                        .fontDesign(appFontDesign)
                        
                        Spacer()
                        
                        if ticketString != "NaN" {
                            Button {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                self.seatToView = seat
                            } label: {
                                Image(systemName: "qrcode")
                                    .font(.title)
                            }
                        }
                    }
                }
                .onDelete(perform: deleteSeat)
            }
            .navigationTitle("Your Seats")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        if show_adding_row {
                            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                            show_adding_row = false
                            newCarriage = ""
                            newSeat = ""
                            newName = ""
                            newTicketPayload = ""
                            newTicketSymbology = ""
                        } else {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            seats_sheet = false
                        }
                    } label: {
                        Image(systemName: show_adding_row ? "arrow.uturn.left" : "xmark")
                            .contentTransition(.symbolEffect(.replace.downUp.wholeSymbol, options: .nonRepeating))
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    if show_adding_row == false {
                        Button {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            show_adding_row = true
                            adding_row_focused_field = .name
                        } label: {
                            Image(systemName: "plus")
                                .contentTransition(.symbolEffect(.replace.downUp.wholeSymbol, options: .nonRepeating))
                        }
                        .buttonStyle(.glassProminent)
                    } else {
                        if newName != "" && ((newSeat != "" && newCarriage != "") || (newTicketPayload != "" && newTicketSymbology != "")) {
                            Button("Save") {
                                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                                addNewSeat()
                                show_adding_row = false
                                selectedPhotoItem = nil
                                processing_steps = .empty
                            }
                            .buttonStyle(.glassProminent)
                        } else {
                            Button("Save") {
                                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                                addNewSeat()
                                show_adding_row = false
                                selectedPhotoItem = nil
                                processing_steps = .empty
                            }
                            .disabled(true)
                        }
                    }
                }
            }
            .sheet(item: $seatToView) { seatString in
                TicketView(seatString: seatString)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
    }
    
    func deleteSeat(offsets: IndexSet) {
        let sortedSeats = train.seats.sorted { seat1, seat2 in
            let parts1 = seat1.split(separator: "-")
            let parts2 = seat2.split(separator: "-")
            
            guard parts1.count >= 2 && parts2.count >= 2 else {
                return seat1.localizedStandardCompare(seat2) == .orderedAscending
            }
            
            let carriage1 = Int(parts1[0]) ?? 0
            let carriage2 = Int(parts2[0]) ?? 0
            
            if carriage1 != carriage2 {
                return carriage1 < carriage2
            }
            
            let seatNum1 = Int(parts1[1].filter { $0.isNumber }) ?? 0
            let seatNum2 = Int(parts2[1].filter { $0.isNumber }) ?? 0
            
            if seatNum1 != seatNum2 {
                return seatNum1 < seatNum2
            }
            
            let seatLetter1 = parts1[1].filter { $0.isLetter }
            let seatLetter2 = parts2[1].filter { $0.isLetter }
            
            if seatLetter1 != seatLetter2 {
                return seatLetter1 < seatLetter2
            }
            
            let name1 = parts1.count > 2 ? parts1.dropFirst(2).joined(separator: "-") : ""
            let name2 = parts2.count > 2 ? parts2.dropFirst(2).joined(separator: "-") : ""
            
            return name1 < name2
        }
        
        let seatsToDelete = offsets.map { sortedSeats[$0] }
        
        for seat in seatsToDelete {
            if let index = train.seats.firstIndex(of: seat) {
                train.seats.remove(at: index)
            }
        }
    }
    
    func addNewSeat() {
        guard !newName.isEmpty else { return }
        
        let formattedCarriage = {
            if newCarriage != "" {
                let cleanedCarriage = newCarriage.filter { $0.isNumber }
                return String(cleanedCarriage.prefix(2))
            } else {
                return "NaN"
            }
        }()
        let formattedSeat = {
            if newSeat != "" {
                let cleanedSeat = newSeat.filter { $0.isLetter || $0.isNumber }
                return String(cleanedSeat.prefix(3)).uppercased()
            } else {
                return "NaN"
            }
        }()
        let formattedName = {
            let cleanedName = newName.filter { $0.isLetter || $0.isNumber }
            return cleanedName.prefix(1).uppercased() + cleanedName.dropFirst().lowercased()
        }()
        let formattedTicket = {
            if newTicketPayload != "" && newTicketSymbology != "" {
                return "\(newTicketSymbology):\(newTicketPayload)"
            } else {
                return "NaN"
            }
        }()
        
        let finalString = "\(formattedCarriage)-\(formattedSeat)-\(formattedName)-\(formattedTicket)"
        print("finalString: \(finalString)")
        train.seats.append(finalString)
        
        newCarriage = ""
        newSeat = ""
        newName = ""
        newTicketPayload = ""
        newTicketSymbology = ""
    }
    
    func processPhoto(item: PhotosPickerItem?) {
        guard let item = item else { return }
        
        Task {
            if let data = try? await item.loadTransferable(type: Data.self),
               let uiImage = UIImage(data: data),
               let fixedImage = fixOrientation(img: uiImage),
               let cgImage = fixedImage.cgImage {
                
                let request = VNDetectBarcodesRequest { request, error in
                    guard let results = request.results as? [VNBarcodeObservation] else { return }
                    
                    if let code = results.first(where: { $0.symbology == .aztec || $0.symbology == .qr }) {
                        
                        DispatchQueue.main.async {
                            processing_steps = .saved
                            print("✅ Scanned \(code.symbology == .aztec ? "Aztec" : "QR")")
                            
                            if let payload = code.payloadStringValue {
                                newTicketPayload = payload
                                newTicketSymbology = symbolToString(code.symbology)
                            }
                        }
                    } else {
                        DispatchQueue.main.async {
                            processing_steps = .error
                            print("❌ No QR/Aztec code found")
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                                processing_steps = .empty
                                selectedPhotoItem = nil
                            }
                        }
                    }
                }
                
                request.revision = VNDetectBarcodesRequestRevision1
                try? VNImageRequestHandler(cgImage: cgImage, options: [:])
                    .perform([request])
            } else {
                await MainActor.run {
                    processing_steps = .error
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        processing_steps = .empty
                        selectedPhotoItem = nil
                    }
                }
            }
        }
    }
}
