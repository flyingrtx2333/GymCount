import SwiftUI

struct PhoneDeveloperToolsView: View {
    var body: some View {
        List {
            Section {
                NavigationLink(String(localized: "同步录像与采样")) { PhoneCaptureView() }
                NavigationLink(String(localized: "采集记录与标注")) { VideoCaptureHistoryView() }
            }
            .listRowBackground(Studio.surface)
        }
        .scrollContentBackground(.hidden)
        .background(Studio.background)
        .navigationTitle(String(localized: "开发者工具"))
        .toolbarBackground(Studio.background, for: .navigationBar)
    }
}
