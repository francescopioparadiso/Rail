import SwiftUI
import SwiftData
import StoreKit

struct TicketView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReview) var requestReview
    
    let seat: Seat
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 0)
            
            VStack(spacing: 16) {
                if let imageData = seat.image, let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()
                        .padding()
                        .background(Color.white)
                        .clipShape(ConcentricRectangle(corners: .concentric(minimum: .fixed(8)), isUniform: true))
                        
                } else {
                    ContentUnavailableView(
                        "No Code",
                        systemImage: "qrcode.viewfinder",
                        description: Text("This seat has no ticket code saved.")
                    )
                        .foregroundStyle(Color.secondary)
                        .frame(maxWidth: .infinity)
                        .padding()
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
                .padding(.vertical, 8).padding(.horizontal, 12)
                .foregroundStyle(.secondary)
            }
            .padding(32)
            
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(appBackgroundColor)
        .presentationDetents([.medium, .large])
        .onAppear {
            ReviewManager.shared.requestReviewIfAppropriate(action: requestReview)
        }
    }
}
