import SwiftUI

@main
struct GymCountPhoneApp: App {
    @StateObject private var store = PhoneWorkoutStore()

    var body: some Scene {
        WindowGroup {
            PhoneContentView()
                .environmentObject(store)
        }
    }
}
