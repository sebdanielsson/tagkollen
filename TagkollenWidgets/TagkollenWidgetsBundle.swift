import SwiftUI
import WidgetKit

@main
struct TagkollenWidgetsBundle: WidgetBundle {
    var body: some Widget {
        SavedTrainWidget()
        StationDeparturesWidget()
        TrainLiveActivity()
    }
}
