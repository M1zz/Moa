import SwiftUI
import UIKit
import CoreImage.CIFilterBuiltins

enum QRCodeRenderer {
    /// Renders a crisp QR code with a 4-module quiet zone on a white background,
    /// suitable for printing on a table card.
    static func image(for string: String, moduleSize: CGFloat = 16) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"

        guard let output = filter.outputImage?
            .transformed(by: CGAffineTransform(scaleX: moduleSize, y: moduleSize)),
              let cgImage = CIContext().createCGImage(output, from: output.extent) else { return nil }

        let margin = moduleSize * 4
        let codeSize = CGSize(width: cgImage.width, height: cgImage.height)
        let canvas = CGSize(width: codeSize.width + margin * 2, height: codeSize.height + margin * 2)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        return UIGraphicsImageRenderer(size: canvas, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: canvas))
            context.cgContext.interpolationQuality = .none
            UIImage(cgImage: cgImage).draw(in: CGRect(origin: CGPoint(x: margin, y: margin), size: codeSize))
        }
    }
}

struct QRCodeView: View {
    let image: UIImage?

    var body: some View {
        if let image {
            Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
                .accessibilityLabel("사진 보내기 QR 코드")
        } else {
            Image(systemName: "qrcode")
                .font(.system(size: 120))
                .foregroundStyle(.secondary)
        }
    }
}
