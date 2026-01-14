import SwiftUI
import SwiftData

struct TicketView: View {
    // MARK: - variables
    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReview) var requestReview
    
    let seat: Seat
    
    // MARK: - main content
    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 0)
            
            VStack(spacing: 16) {
                if let imageData = seat.image, let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()
                        .frame(width: 300, height: 300)
                        .padding()
                        .background(Color.white)
                        .cornerRadius(28)
                } else {
                    ContentUnavailableView("No Code", systemImage: "qrcode.viewfinder")
                        .frame(width: 300, height: 300)
                }
                
                HStack {
                    Text(seat.name)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    
                    if !seat.carriage.isEmpty && !seat.number.isEmpty {
                        Spacer()
                        
                        HStack (spacing: 16) {
                            HStack(spacing: 8) {
                                Image(systemName: "train.side.rear.car")
                                Text(seat.carriage)
                            }
                            
                            HStack(spacing: 8) {
                                Image(systemName: "carseat.left.fill")
                                Text(seat.number)
                            }
                        }
                        .font(.body)
                    }
                }
                .fontDesign(appFontDesign)
                .padding(.vertical).padding(.horizontal, 48)
                .foregroundStyle(.secondary)
            }
            .padding(.top, 40)
            
            Spacer(minLength: 0)
        }
        .presentationDetents([.medium, .large])
    }
}
