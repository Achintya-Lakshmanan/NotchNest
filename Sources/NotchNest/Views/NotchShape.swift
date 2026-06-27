import SwiftUI

/// A black "card" that hangs from the top of the screen: a flush, full-width
/// flat top (so it blends into the physical notch with no gaps) and smoothly
/// rounded bottom corners.
struct NotchShape: Shape {
    var bottomCornerRadius: CGFloat = 22

    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let bc = min(bottomCornerRadius, min(w / 2, h))

        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: w, y: 0))          // flush top edge
        path.addLine(to: CGPoint(x: w, y: h - bc))     // right side
        path.addQuadCurve(to: CGPoint(x: w - bc, y: h),
                          control: CGPoint(x: w, y: h)) // bottom-right
        path.addLine(to: CGPoint(x: bc, y: h))          // bottom edge
        path.addQuadCurve(to: CGPoint(x: 0, y: h - bc),
                          control: CGPoint(x: 0, y: h))  // bottom-left
        path.closeSubpath()
        return path
    }
}
