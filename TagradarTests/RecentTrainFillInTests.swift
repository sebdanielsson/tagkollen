import Foundation
@testable import Tagradar
import Testing

/// `RecentTrain.fillIn` is what keeps the Recent tab readable for a run starred before its journey
/// arrived: the favorite it renders from is empty, while the record beside it still knows the route
/// and the times. A successful load fills the favorite in too — this is what the offline case has.
@Suite("Recent train fill-in")
struct RecentTrainFillInTests {
    private static let day = Date(timeIntervalSince1970: 1_757_000_000)

    private func recent() -> RecentTrain {
        var recent = RecentTrain(key: TrainKey(ident: "537", departureDate: Self.day), journey: nil)
        recent.originSignature = "Cst"
        recent.destinationSignature = "G"
        recent.productName = "SJ Snabbtåg"
        recent.scheduledDeparture = Self.day
        recent.scheduledArrival = Self.day.addingTimeInterval(3 * 3600)
        return recent
    }

    private func emptyFavorite() -> FavoriteTrain {
        FavoriteTrain(key: TrainKey(ident: "537", departureDate: Self.day), journey: nil)
    }

    @Test("A favorite starred before its journey loaded takes the record's summary")
    func fillsAnEmptyFavorite() {
        let favorite = emptyFavorite()
        #expect(recent().fillIn(favorite))
        #expect(favorite.originSignature == "Cst")
        #expect(favorite.destinationSignature == "G")
        #expect(favorite.productName == "SJ Snabbtåg")
        #expect(favorite.scheduledDeparture == Self.day)
        #expect(favorite.scheduledArrival == Self.day.addingTimeInterval(3 * 3600))
    }

    /// The favorite is the one the user has been editing — a trip segment lives there and the
    /// record knows nothing about it — so its own values always win.
    @Test("A favorite that already has a summary keeps it")
    func keepsWhatTheFavoriteAlreadyHas() {
        let favorite = emptyFavorite()
        favorite.originSignature = "U"
        favorite.productName = "Mälartåg"
        #expect(recent().fillIn(favorite))
        #expect(favorite.originSignature == "U")
        #expect(favorite.productName == "Mälartåg")
        #expect(favorite.destinationSignature == "G")
    }

    /// The sweep in `MapTrainsCard` saves only when something changed, so "nothing to do" has to be
    /// distinguishable from a repair — otherwise every pass through the card writes to the store.
    @Test("Filling in a complete favorite reports no change")
    func reportsNoChangeWhenNothingIsMissing() {
        let favorite = emptyFavorite()
        recent().fillIn(favorite)
        #expect(!recent().fillIn(favorite))
    }

    /// A record with gaps of its own cannot invent values, and must not report a repair it did not
    /// make: that would be a store write on every pass for a favorite that stays just as empty.
    @Test("A record with nothing to give reports no change")
    func reportsNoChangeWhenTheRecordIsEmptyToo() {
        let bare = RecentTrain(key: TrainKey(ident: "537", departureDate: Self.day), journey: nil)
        #expect(!bare.fillIn(emptyFavorite()))
    }
}
