//
//  ContentView.swift
//  ARGame
//
//  Created by Vansh Patel on 2/16/25.
//

import SwiftUI
import RealityKit


struct ContentView: View {
    @StateObject private var gameSettings = GameSettings()
    @State private var showingSettings = false
    
    var body: some View {
        GameView(gameSettings: gameSettings, showingSettings: $showingSettings)
            .sheet(isPresented: $showingSettings) {
                NavigationView {
                    SettingsView(gameSettings: gameSettings)
                        .navigationTitle("Settings")
                        .navigationBarItems(trailing:
                            Button("Done") {
                                showingSettings = false
                            }
                        )
                }
            }
    }
}

#Preview {
    ContentView()
}
