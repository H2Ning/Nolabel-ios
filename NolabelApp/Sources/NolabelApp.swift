import SwiftUI

@main
struct NolabelApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
                .ignoresSafeArea()
        }
    }
}

struct ContentView: View {
    var body: some View {
        WebView()
            .background(
                Color(
                    red: 7.0 / 255.0,
                    green: 11.0 / 255.0,
                    blue: 9.0 / 255.0
                )
            )
            .ignoresSafeArea()
    }
}
