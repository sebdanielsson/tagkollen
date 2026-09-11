import SwiftUI
import WidgetKit

@main
struct TagradarWidgetsBundle: WidgetBundle {
    var body: some Widget {
        SavedTrainWidget()
        StationDeparturesWidget()
        TrainLiveActivity()
    }
}
