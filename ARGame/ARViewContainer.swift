import SwiftUI
import RealityKit
import ARKit
import Combine

struct ARViewContainer: UIViewRepresentable {
    @Binding var score: Int
    @Binding var remainingAmmo: Int
    @Binding var playerHealth: Int
    @Binding var isReloading: Bool
    var onGameOver: () -> Void
    
    
    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        
        // Setup AR scene
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        arView.session.run(config)
        
        // Initialize monster spawner with coordinator
        let spawner = MonsterSpawner(arView: arView, coordinator: context.coordinator)
        context.coordinator.monsterSpawner = spawner
        
        // Spawn initial monster
        Task {
            await spawner.spawnMonster()
        }
        
        // Add tap gesture for shooting
        let tapGesture = UITapGestureRecognizer(target: context.coordinator,
                                               action: #selector(Coordinator.handleTap))
        arView.addGestureRecognizer(tapGesture)
        
        // Start monitoring for bullet collisions
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            context.coordinator.checkBulletCollisions(arView: arView)
        }
        
        return arView
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {
        DispatchQueue.main.async {
            context.coordinator.checkBulletCollisions(arView: uiView)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject {
        var parent: ARViewContainer
        var monsterSpawner: MonsterSpawner?
        
        init(_ parent: ARViewContainer) {
            self.parent = parent
        }
        
        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            // Don't allow shooting while reloading
            guard !parent.isReloading else { return }
            guard parent.remainingAmmo > 0 else { return }
            guard let arView = recognizer.view as? ARView else { return }
            
            // Get the camera transform
            guard let camera = arView.session.currentFrame?.camera else { return }
            let cameraTransform = camera.transform
            
            // Get the ray through the center of the screen (where crosshair is)
            let screenCenter = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY + 30)  // Added 30px to adjust for crosshair offset
            
            // Perform hit test to get the point in 3D space where the crosshair is pointing
            let hitTestResults = arView.hitTest(screenCenter, types: .featurePoint)
            
            // Get bullet start position (camera position)
            let bulletStartPosition = simd_make_float3(cameraTransform.columns.3)
            
            // Calculate direction to the hit point or use a default distance if no hit
            var bulletEndPosition: SIMD3<Float>
            if let firstHitResult = hitTestResults.first {
                // Use the actual hit point
                bulletEndPosition = simd_make_float3(firstHitResult.worldTransform.columns.3)
            } else {
                // If no hit, project a point 5 meters in front of the camera along the ray
                let rayDirection = raycastDirectionFromScreen(screenCenter, in: arView)
                bulletEndPosition = bulletStartPosition + (rayDirection * 5)
            }
            
            // Calculate direction from start to end position
            let direction = normalize(bulletEndPosition - bulletStartPosition)
            
            // Create bullet entity
            let bullet = ModelEntity(mesh: .generateSphere(radius: 0.05))
            bullet.model?.materials = [SimpleMaterial(color: .black, isMetallic: true)]
            
            // Create anchor at start position
            let bulletAnchor = AnchorEntity(world: bulletStartPosition)
            bulletAnchor.addChild(bullet)
            arView.scene.addAnchor(bulletAnchor)
            
            // Check for monster hits
            var monsterHit = false
            
            for anchor in arView.scene.anchors {
                for entity in anchor.children {
                    if let monster = entity as? MonsterEntity {
                        let monsterPosition = monster.position
                        let radius: Float = 1.0
                        if rayIntersectsSphere(rayOrigin: bulletStartPosition,
                                             rayDirection: direction,
                                             sphereCenter: monsterPosition,
                                             sphereRadius: radius) {
                            handleMonsterHit(monster)
                            monsterHit = true
                            break
                        }
                    }
                }
                if monsterHit { break }
            }
            
            // Animate bullet to end position
            let finalPosition = bulletStartPosition + (direction * 5) // 5 meters out
            bullet.move(to: Transform(translation: finalPosition), relativeTo: nil, duration: 0.5)
            
            // Remove bullet after animation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                bulletAnchor.removeFromParent()
            }
            
            parent.remainingAmmo -= 1
        }
        
        func raycastDirectionFromScreen(_ point: CGPoint, in arView: ARView) -> SIMD3<Float> {
            guard let camera = arView.session.currentFrame?.camera else {
                return SIMD3<Float>(0, 0, -1)
            }
            
            // Get projection matrix from the camera
            let projectionMatrix = camera.projectionMatrix
            
            // Convert screen point to normalized point (-1 to 1)
            let viewBounds = arView.bounds
            let normalizedPoint = CGPoint(
                x: (point.x / viewBounds.width) * 2 - 1,
                y: -((point.y / viewBounds.height) * 2 - 1)  // Flip Y coordinate
            )
            
            // Create direction in camera space
            var rayDirection = SIMD3<Float>(
                Float(normalizedPoint.x),
                Float(normalizedPoint.y),
                -1.0  // Forward direction in camera space
            )
            
            // Unproject using projection matrix
            rayDirection.x *= -rayDirection.z * tan(camera.intrinsics[0][0])
            rayDirection.y *= -rayDirection.z * tan(camera.intrinsics[1][1])
            
            // Transform to world space
            let cameraTransform = camera.transform
            let worldDirection = SIMD3<Float>(
                cameraTransform.columns.0[0] * rayDirection.x + cameraTransform.columns.1[0] * rayDirection.y + cameraTransform.columns.2[0] * rayDirection.z,
                cameraTransform.columns.0[1] * rayDirection.x + cameraTransform.columns.1[1] * rayDirection.y + cameraTransform.columns.2[1] * rayDirection.z,
                cameraTransform.columns.0[2] * rayDirection.x + cameraTransform.columns.1[2] * rayDirection.y + cameraTransform.columns.2[2] * rayDirection.z
            )
            
            return normalize(worldDirection)
        }
        
        func rayIntersectsSphere(rayOrigin: SIMD3<Float>,
                               rayDirection: SIMD3<Float>,
                               sphereCenter: SIMD3<Float>,
                               sphereRadius: Float) -> Bool {
            let oc = rayOrigin - sphereCenter
            let a = simd_dot(rayDirection, rayDirection)
            let b = 2.0 * simd_dot(oc, rayDirection)
            let c = simd_dot(oc, oc) - sphereRadius * sphereRadius
            let discriminant = b * b - 4 * a * c
            
            return discriminant > 0
        }
        
        func handleMonsterHit(_ monster: MonsterEntity) {
            monster.takeDamage(amount: 25)
            
            print("handleMonsterHit called for monster:", monster)
            print("Monster HP after damage:", monster.hitPoints)
            
            if monster.hitPoints <= 0 {
                print("Monster defeated!")
            }
        }
        
        func checkBulletCollisions(arView: ARView) {
            // Get current camera position
            guard let camera = arView.session.currentFrame?.camera else { return }
            let playerPosition = simd_make_float3(camera.transform.columns.3)
            
            for anchor in arView.scene.anchors {
                if let bullet = anchor as? MonsterBulletEntity {
                    // Calculate distance from bullet to actual camera position
                    let distance = simd_distance(bullet.position, playerPosition)
                    
                    // Smaller collision radius (0.3 might have been too large)
                    let collisionRadius: Float = 0.2
                    
                    if distance < collisionRadius {
                        print("Hit detected! Distance: \(distance)")
                        bullet.removeFromParent()
                        parent.playerHealth -= 1
                        
                        if parent.playerHealth <= 0 {
                            parent.onGameOver()
                        }
                    }
                }
            }
        }
    }
}
