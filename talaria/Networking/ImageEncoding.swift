import UIKit

enum ImageEncoding {
    /// Downscale to a sane size for a vision model and encode as a JPEG data URL.
    static func dataURL(_ image: UIImage, maxDimension: CGFloat = 1600, quality: CGFloat = 0.8) -> String? {
        let scale = min(1, maxDimension / max(image.size.width, image.size.height))
        let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        guard let jpeg = resized.jpegData(compressionQuality: quality) else { return nil }
        return "data:image/jpeg;base64," + jpeg.base64EncodedString()
    }

    static func image(fromDataURL url: String) -> UIImage? {
        guard url.hasPrefix("data:image/"), let comma = url.firstIndex(of: ",") else { return nil }
        guard let data = Data(base64Encoded: String(url[url.index(after: comma)...])) else { return nil }
        return UIImage(data: data)
    }
}
