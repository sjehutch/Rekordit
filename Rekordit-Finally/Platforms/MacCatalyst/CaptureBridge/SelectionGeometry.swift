import Foundation

func draggedRect(from start: CGPoint, to end: CGPoint, within bounds: CGRect) -> CGRect {
    let x = min(max(end.x, bounds.minX), bounds.maxX)
    let y = min(max(end.y, bounds.minY), bounds.maxY)
    return CGRect(x: min(start.x, x), y: min(start.y, y),
                  width: abs(x - start.x), height: abs(y - start.y))
}

func movedRect(_ rect: CGRect, dx: CGFloat, dy: CGFloat, within bounds: CGRect) -> CGRect {
    CGRect(x: min(max(rect.minX + dx, bounds.minX), bounds.maxX - rect.width),
           y: min(max(rect.minY + dy, bounds.minY), bounds.maxY - rect.height),
           width: rect.width, height: rect.height)
}

func resizedRect(_ rect: CGRect, handle: Int, to point: CGPoint, within bounds: CGRect) -> CGRect {
    var left = rect.minX, right = rect.maxX, top = rect.minY, bottom = rect.maxY
    let x = min(max(point.x, bounds.minX), bounds.maxX)
    let y = min(max(point.y, bounds.minY), bounds.maxY)
    if [0, 6, 7].contains(handle) { left = min(x, right - 24) }
    if [2, 3, 4].contains(handle) { right = max(x, left + 24) }
    if [0, 1, 2].contains(handle) { top = min(y, bottom - 24) }
    if [4, 5, 6].contains(handle) { bottom = max(y, top + 24) }
    return CGRect(x: left, y: top, width: right - left, height: bottom - top)
}
