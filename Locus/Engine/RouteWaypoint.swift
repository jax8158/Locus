import Foundation

struct RouteWaypoint: Identifiable, Hashable {
    let id: UUID
    var pathIndex: Int
    var speedMultiplier: Double

    init(id: UUID = UUID(), pathIndex: Int, speedMultiplier: Double = 1.0) {
        self.id = id
        self.pathIndex = pathIndex
        self.speedMultiplier = speedMultiplier
    }
}
