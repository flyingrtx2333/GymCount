#if DEBUG
import SwiftUI

struct PhoneDeveloperToolsView: View {
    var body: some View {
        List {
            Section {
                NavigationLink(String(localized: "同步录像与采样")) { PhoneCaptureView() }
                NavigationLink(String(localized: "采集记录与标注")) { VideoCaptureHistoryView() }
            }
            .recordSectionStyle()
        }
        .listStyle(.plain).recordListStyle().font(Studio.Fonts.body).recordCanvasSpacing()
        .navigationTitle(String(localized: "开发者工具"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Studio.background, for: .navigationBar)
    }
}
#endif
