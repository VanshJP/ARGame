import SwiftUI
import RealityKit
import ARKit
import Combine
import QuartzCore

class GameSettings: ObservableObject {
    @Published var monsterCount: Int = 5
    @Published var timeLimit: Int = 120
    @Published var ammoCount: Int = 10
    @Published var isLeftHanded: Bool = false
}

struct GameView: View {
    @ObservedObject var gameSettings: GameSettings
       @State private var remainingAmmo = 10
       @State private var remainingTime = 10
       @State private var score: Int = 0
       @State private var isGameActive = true
       @State private var playerHealth = 10
       @State private var bestScore: Int = UserDefaults.standard.integer(forKey: "BestScore")
       @Binding var showingSettings: Bool
       
       // Reload states
       @State private var isReloading = false
       @State private var reloadProgress: Double = 0
       private let reloadDuration: Double = 3.0
       
       // Add initializer
       init(gameSettings: GameSettings, showingSettings: Binding<Bool>) {
           _gameSettings = ObservedObject(wrappedValue: gameSettings)
           _showingSettings = showingSettings
       }
        
     
    
    var body: some View {
        ZStack {
            if isGameActive {
                ARViewContainer(score: $score,
                              remainingAmmo: $remainingAmmo,
                              playerHealth: $playerHealth,
                              isReloading: $isReloading,
                              onGameOver: {
                    gameOver()
                })
                .edgesIgnoringSafeArea(.all)
                
                // Game UI overlays
                VStack {
                    // Top area
                    HStack {
                        // Left side - Ammo and Score
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Ammo: \(remainingAmmo)")
                            Text("Score: \(score)")
                        }
                        .padding()
                        .background(Color.black.opacity(0.5))
                        .foregroundColor(.white)
                        .cornerRadius(10)
                        
                        Spacer()
                        
                        // Right side - Settings
                        Button(action: { showingSettings = true }) {
                            Image(systemName: "gearshape.fill")
                                .font(.title)
                                .foregroundColor(.white)
                                .padding()
                                .background(Color.black.opacity(0.5))
                                .clipShape(Circle())
                        }
                    }
                    .padding()
                    
                    Spacer()
                    
                    // Bottom area
                    HStack {
                        if gameSettings.isLeftHanded {
                            ReloadButton(isReloading: $isReloading,
                                       reloadProgress: $reloadProgress,
                                       remainingAmmo: $remainingAmmo,
                                       gameSettings: gameSettings,
                                       reloadDuration: reloadDuration)
                            
                            Spacer()
                            
                            HealthHeartsView(health: playerHealth)
                        } else {
                            HealthHeartsView(health: playerHealth)
                            
                            Spacer()
                            
                            ReloadButton(isReloading: $isReloading,
                                       reloadProgress: $reloadProgress,
                                       remainingAmmo: $remainingAmmo,
                                       gameSettings: gameSettings,
                                       reloadDuration: reloadDuration)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom)
                }
                
                CrosshairView(isReloading: isReloading, reloadProgress: reloadProgress)
                    .position(x: UIScreen.main.bounds.width / 2,
                             y: UIScreen.main.bounds.height / 2 - 30)
            } else {
                GameOverView(score: score,
                           bestScore: bestScore,
                           restartGame: restartGame)
            }
        }
        .onAppear {
            remainingAmmo = gameSettings.ammoCount
            remainingTime = gameSettings.timeLimit
            playerHealth = 10
        }
    }
    
    func gameOver() {
        isGameActive = false
        if score > bestScore {
            bestScore = score
            UserDefaults.standard.set(bestScore, forKey: "BestScore")
        }
    }
    
    func restartGame() {
        score = 0
        playerHealth = 10
        remainingAmmo = gameSettings.ammoCount
        isGameActive = true
    }
}


// Reload

struct ReloadButton: View {
    @Binding var isReloading: Bool
    @Binding var reloadProgress: Double
    @Binding var remainingAmmo: Int
    @ObservedObject var gameSettings: GameSettings
    let reloadDuration: Double
    
    // Local state
    @State private var startTime: Date?
    @State private var displayLinkTarget: DisplayLinkTarget?
    @State private var displayLink: CADisplayLink?
    @State private var isPressed = false
    
    var body: some View {
        Button(action: {}) {
            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.5))
                    .frame(width: 60, height: 60)
                
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 24))
                    .foregroundColor(isReloading ? .gray : .white)
            }
            .padding()
            .clipShape(Circle())
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPressed {
                        startReload()
                    }
                }
                .onEnded { _ in
                    endReload()
                }
        )
        .onDisappear {
            stopDisplayLink()
        }
    }
    
    private func startReload() {
        guard !isReloading && remainingAmmo < gameSettings.ammoCount else { return }
        
        isPressed = true
        isReloading = true
        reloadProgress = 0
        startTime = Date()
        
        setupDisplayLink()
    }
    
    private func setupDisplayLink() {
        stopDisplayLink()  // Clean up any existing display link
        
        let target = DisplayLinkTarget {
            updateProgress()
        }
        displayLinkTarget = target
        
        let displayLink = CADisplayLink(target: target, selector: #selector(DisplayLinkTarget.handleDisplayLink(_:)))
        displayLink.add(to: .main, forMode: .common)
        self.displayLink = displayLink
    }
    
    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
        displayLinkTarget = nil
    }
    
    private func updateProgress() {
        guard let startTime = startTime, isPressed else { return }
        
        let elapsedTime = Date().timeIntervalSince(startTime)
        reloadProgress = min(elapsedTime / reloadDuration, 1.0)
        
        if reloadProgress >= 1.0 {
            completeReload()
        }
    }
    
    private func endReload() {
        isPressed = false
        if reloadProgress >= 0.9 {
            completeReload()
        } else {
            cancelReload()
        }
    }
    
    private func completeReload() {
        if isReloading {
            remainingAmmo = gameSettings.ammoCount
            print("Reload complete! Ammo now: \(remainingAmmo)")
        }
        resetReloadState()
    }
    
    private func cancelReload() {
        print("Reload cancelled")
        resetReloadState()
    }
    
    private func resetReloadState() {
        stopDisplayLink()
        startTime = nil
        isReloading = false
        reloadProgress = 0
        isPressed = false
    }
}

final class DisplayLinkTarget: NSObject {
    let callback: () -> Void
    
    init(callback: @escaping () -> Void) {
        self.callback = callback
        super.init()
    }
    
    @objc public func handleDisplayLink(_ displayLink: CADisplayLink) {
        callback()
    }
}




// New CrosshairView component

struct CrosshairView: View {
    var isReloading: Bool
    var reloadProgress: Double
    
    var body: some View {
        ZStack {
            // Reload progress circle
            if isReloading {
                Circle()
                    .stroke(Color.white.opacity(0.3), lineWidth: 3)
                    .frame(width: 70, height: 70)
                
                Circle()
                    .trim(from: 0, to: CGFloat(reloadProgress))
                    .stroke(Color.green, lineWidth: 3)
                    .frame(width: 70, height: 70)
                    .rotationEffect(.degrees(-90))
            }
            
            // Regular crosshair
            Circle()
                .stroke(Color.white, lineWidth: 2)
                .frame(width: 50, height: 50)
            
            VStack {
                Rectangle()
                    .frame(width: 2, height: 20)
                    .foregroundColor(.white)
            }
            
            HStack {
                Rectangle()
                    .frame(width: 20, height: 2)
                    .foregroundColor(.white)
            }
        }
    }
}



// New GameOverView component
struct GameOverView: View {
    let score: Int
    let bestScore: Int
    let restartGame: () -> Void
    
    var body: some View {
        VStack {
            Text("GAME OVER")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .padding(.bottom, 20)
            
            Text("Score: \(score)")
                .font(.title)
                .foregroundColor(.white)
            
            Text("Best Score: \(bestScore)")
                .font(.title2)
                .foregroundColor(.white)
                .padding(.bottom, 30)
            
            Button(action: restartGame) {
                Text("RESTART")
                    .font(.title)
                    .bold()
                    .padding()
                    .background(Color.white)
                    .foregroundColor(.red)
                    .cornerRadius(10)
            }
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.red.ignoresSafeArea())
    }
}


struct HeartView: View {
    let filled: Bool
    let faded: Bool
    
    var body: some View {
        Image(systemName: "heart.fill")
            .font(.system(size: 30))
            .foregroundColor(heartColor)
    }
    
    private var heartColor: Color {
        if filled {
            return .red
        } else if faded {
            return .red.opacity(0.5)
        } else {
            return .gray
        }
    }
}



struct HealthHeartsView: View {
    let health: Int  // Health from 0-10
    
    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<5) { index in
                HeartView(
                    filled: health >= (index * 2 + 2),
                    faded: health == (index * 2 + 1)
                )
            }
        }
        .padding()
        .background(Color.black.opacity(0.5))
        .cornerRadius(15)
    }
}



//
//  SettingsView.swift
//  ARGame
//
struct SettingsView: View {
    @ObservedObject var gameSettings: GameSettings
    
    var body: some View {
        Form {
            Section(header: Text("Game Settings")) {
                Stepper("Monster Count: \(gameSettings.monsterCount)",
                        value: $gameSettings.monsterCount, in: 1...20)
                
                Stepper("Time Limit: \(gameSettings.timeLimit) seconds",
                        value: $gameSettings.timeLimit, in: 30...300, step: 30)
                
                Stepper("Ammo Count: \(gameSettings.ammoCount)",
                        value: $gameSettings.ammoCount, in: 5...50, step: 5)
            }
            
            Section(header: Text("Controls")) {
                Toggle("Left-handed Mode", isOn: $gameSettings.isLeftHanded)
                    .padding(.vertical, 4)
            }
        }
    }
}
