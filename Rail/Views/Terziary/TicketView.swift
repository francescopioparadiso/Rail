import SwiftUI

struct TicketView: View {
    let seatString: String
    @State private var qrImage: UIImage?
    @State private var ticketSymbology: String = ""
    
    var body: some View {
        let components = seatString.split(separator: "-")
        let carriageString = components[0]
        let seatString = components[1]
        let nameString = components[2]
        let ticketString = components[3]
        let ticketSymbology = String(ticketString.split(separator: ":").first ?? "")
        let ticketPayload = String(ticketString.split(separator: ":").last ?? "")
        
        
        VStack(spacing: 24) {
            Spacer(minLength: 0)
            
            if let image = qrImage {
                VStack(spacing: 16) {
                    Image(uiImage: image)
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()
                        .frame(width: 300, height: 300)
                        .padding()
                        .background(Color.white)
                        .cornerRadius(28)
                    
                    HStack {
                        Text(nameString)
                            .font(.headline)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        
                        if carriageString != "NaN" && seatString != "NaN" {
                            Spacer()
                            
                            HStack (spacing: 16) {
                                HStack(spacing: 8) {
                                    Image(systemName: "train.side.rear.car")
                                    Text(carriageString)
                                }
                                
                                HStack(spacing: 8) {
                                    Image(systemName: "carseat.left.fill")
                                    Text(seatString)
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
            } else {
                ProgressView()
                    .onAppear {
                        generateTicket(ticketSymbology: ticketSymbology, ticketPayload: ticketPayload)
                    }
            }
            
            Spacer(minLength: 0)
        }
        .presentationDetents([.medium])
    }
    
    private func generateTicket(ticketSymbology: String, ticketPayload: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            let context = CIContext()
            
            let filter: CIFilter
            if ticketSymbology == "qr" {
                filter = CIFilter.qrCodeGenerator()
            } else {
                filter = CIFilter.aztecCodeGenerator()
            }
            filter.setValue(ticketPayload.data(using: .utf8), forKey: "inputMessage")
            
            if let outputImage = filter.outputImage {
                let transform = CGAffineTransform(scaleX: 10, y: 10)
                let scaledImage = outputImage.transformed(by: transform)
                
                if let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) {
                    let uiImage = UIImage(cgImage: cgImage)
                    DispatchQueue.main.async {
                        self.qrImage = uiImage
                    }
                }
            }
        }
    }
}
