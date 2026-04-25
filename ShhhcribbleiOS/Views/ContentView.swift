import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            HistoryView()
                .tabItem { Label("History", systemImage: "clock") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}

#Preview { ContentView() }
