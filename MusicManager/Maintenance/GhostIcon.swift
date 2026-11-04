import SwiftUI

struct GhostShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + h * 0.5))
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + h * 0.5),
            control1: CGPoint(x: rect.minX, y: rect.minY - h * 0.17),
            control2: CGPoint(x: rect.maxX, y: rect.minY - h * 0.17)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + w * 0.833, y: rect.minY + h * 0.82))
        path.addLine(to: CGPoint(x: rect.minX + w * 0.667, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + w * 0.5, y: rect.minY + h * 0.82))
        path.addLine(to: CGPoint(x: rect.minX + w * 0.333, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + w * 0.167, y: rect.minY + h * 0.82))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        let eyeW = w * 0.16
        let eyeH = h * 0.2
        let eyeY = rect.minY + h * 0.3
        path.addEllipse(in: CGRect(x: rect.minX + w * 0.26, y: eyeY, width: eyeW, height: eyeH))
        path.addEllipse(in: CGRect(x: rect.minX + w * 0.58, y: eyeY, width: eyeW, height: eyeH))
        return path
    }
}

struct GhostIcon: View {
    var height: CGFloat = 18
    var color: Color = .primary

    var body: some View {
        GhostShape()
            .fill(color, style: FillStyle(eoFill: true))
            .frame(width: height * 0.85, height: height)
    }
}
