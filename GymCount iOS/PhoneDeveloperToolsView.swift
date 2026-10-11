import SwiftUI

struct PhoneDeveloperToolsView: View {
    var body: some View {
        List {
            Section {
                NavigationLink("同步录像与采样") { PhoneCaptureView() }
                NavigationLink("采集记录与标注") { VideoCaptureHistoryView() }
            }
            .listRowBackground(Studio.surface)
        }
        .scrollContentBackground(.hidden)
        .background(Studio.background)
        .navigationTitle("开发者工具")
        .toolbarBackground(Studio.background, for: .navigationBar)
    }
}
