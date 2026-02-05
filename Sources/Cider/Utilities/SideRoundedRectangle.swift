import SwiftUI

struct SideRoundedRectangle: Shape {
    let radius: CGFloat
    let edge: SidebarEdge

    func path(in rect: CGRect) -> Path {
        let r = min(radius, min(rect.width, rect.height) / 2)
        let minX = rect.minX
        let maxX = rect.maxX
        let minY = rect.minY
        let maxY = rect.maxY
        let roundRight = edge == .left
        let roundLeft = edge == .right

        var path = Path()
        path.move(to: CGPoint(x: minX, y: minY))

        // Bottom edge to right
        if roundRight {
            path.addLine(to: CGPoint(x: maxX - r, y: minY))
            path.addQuadCurve(to: CGPoint(x: maxX, y: minY + r),
                              control: CGPoint(x: maxX, y: minY))
        } else {
            path.addLine(to: CGPoint(x: maxX, y: minY))
        }

        // Right edge up
        if roundRight {
            path.addLine(to: CGPoint(x: maxX, y: maxY - r))
            path.addQuadCurve(to: CGPoint(x: maxX - r, y: maxY),
                              control: CGPoint(x: maxX, y: maxY))
        } else {
            path.addLine(to: CGPoint(x: maxX, y: maxY))
        }

        // Top edge to left
        if roundLeft {
            path.addLine(to: CGPoint(x: minX + r, y: maxY))
            path.addQuadCurve(to: CGPoint(x: minX, y: maxY - r),
                              control: CGPoint(x: minX, y: maxY))
        } else {
            path.addLine(to: CGPoint(x: minX, y: maxY))
        }

        // Left edge down
        if roundLeft {
            path.addLine(to: CGPoint(x: minX, y: minY + r))
            path.addQuadCurve(to: CGPoint(x: minX + r, y: minY),
                              control: CGPoint(x: minX, y: minY))
        } else {
            path.addLine(to: CGPoint(x: minX, y: minY))
        }

        path.closeSubpath()
        return path
    }
}
