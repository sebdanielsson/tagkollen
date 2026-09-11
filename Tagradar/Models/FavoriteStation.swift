import Foundation
import SwiftData

/// A starred station, shown first in the quick-station row and in the Saved list.
@Model
final class FavoriteStation {
    @Attribute(.unique) var signature: String
    var name: String
    var createdAt: Date

    init(signature: String, name: String) {
        self.signature = signature
        self.name = name
        createdAt = .now
    }
}
