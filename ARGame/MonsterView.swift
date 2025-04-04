import RealityKit
import Combine
import SwiftUI

class MonsterEntity: Entity, HasModel, HasCollision {
    var hitPoints: Int = 100
    var isAlive: Bool = true
    var healthBar: Entity?
    var onMonsterDeath: (() -> Void)?
    private var collisionBox: ModelEntity?
    weak var coordinator: ARViewContainer.Coordinator?

    required init() {
        super.init()
        setupCollision()
    }

    private func setupCollision() {
        let boxSize: Float = 1.0
        let collisionMesh = MeshResource.generateBox(size: [boxSize, boxSize, boxSize])
        collisionBox = ModelEntity(mesh: collisionMesh)

        collisionBox?.model?.materials = [SimpleMaterial(color: .clear, isMetallic: false)]
        collisionBox?.generateCollisionShapes(recursive: true)

        if let collisionBox = collisionBox {
            self.addChild(collisionBox)
        }
    }

    convenience init(named modelName: String, coordinator: ARViewContainer.Coordinator) async {
        self.init()
        self.coordinator = coordinator

        do {
            let modelEntity = try await ModelEntity(named: modelName)
            self.addChild(modelEntity)

            let scale: Float = 1.0
            self.scale = [scale, scale, scale]
            
            self.generateCollisionShapes(recursive: true)

            let monsterHeight = modelEntity.visualBounds(relativeTo: nil).max.y

            let healthBar = MonsterEntity.createHealthBar()
            await MainActor.run {
                healthBar.position = SIMD3<Float>(0, monsterHeight + 0.2, 0)
                self.addChild(healthBar)
                self.healthBar = healthBar
            }
        } catch {
            print("Error loading monster: \(error)")
        }
    }

    func takeDamage(amount: Int) {
        Task { @MainActor in
            hitPoints -= amount
            updateHealthBar()

            print("Monster took \(amount) damage, remaining HP: \(hitPoints)")

            if hitPoints <= 0 {
                isAlive = false

                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }

                    print("Monster defeated! Updating score before removal.")

           

                    self.onMonsterDeath?()
                }
            }
        }
    }

    func updateHealthBar() {
        guard let healthBar = healthBar else { return }
        let percentage = max(0, Float(hitPoints) / 100.0)

        Task { @MainActor in
            if healthBar.children.count >= 2,
               let greenBar = healthBar.children[1] as? ModelEntity {
                greenBar.transform.scale = SIMD3<Float>(percentage, 1, 1)
                greenBar.position.x = (1 - percentage) * -0.5

                let red = 1.0 - percentage
                let green = percentage
                let healthColor = UIColor(red: CGFloat(red), green: CGFloat(green), blue: 0, alpha: 1.0)
                greenBar.model?.materials = [SimpleMaterial(color: healthColor, isMetallic: false)]
            }
        }
    }

    static func createHealthBar() -> Entity {
        let barContainer = Entity()

        let barWidth: Float = 1.0
        let barHeight: Float = 0.1
        let barDepth: Float = 0.05

        let backgroundBar = ModelEntity(mesh: .generateBox(size: [barWidth, barHeight, barDepth]))
        backgroundBar.model?.materials = [SimpleMaterial(color: .darkGray, isMetallic: false)]
        barContainer.addChild(backgroundBar)

        let healthBar = ModelEntity(mesh: .generateBox(size: [barWidth, barHeight, barDepth]))
        healthBar.model?.materials = [SimpleMaterial(color: .green, isMetallic: false)]
        healthBar.position = SIMD3<Float>(0, 0, 0.001)

        barContainer.addChild(healthBar)

        return barContainer
    }

    func startShooting(at player: Entity, in arView: ARView) {
        Task {
            while isAlive {
                let randomDelay = UInt64(Double.random(in: 1.0...2.5) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: randomDelay)
                await shootBullet(at: player, in: arView)
            }
        }
    }

    private func shootBullet(at player: Entity, in arView: ARView) async {
        let bullet = MonsterBulletEntity()

        await MainActor.run {
            bullet.position = self.position
            arView.scene.addAnchor(bullet)
        }

        let direction = normalize(player.position - self.position)
        let moveTo = Transform(translation: self.position + direction * 5.0)

        bullet.move(to: moveTo, relativeTo: nil, duration: 2.0, timingFunction: .linear)

        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run {
                bullet.removeFromParent()
            }
        }
    }





}

class MonsterBulletEntity: Entity, HasModel, HasCollision, HasAnchoring {
    required init() {
        super.init()
        
        let bulletRadius: Float = 0.1
        let bullet = ModelEntity(mesh: .generateSphere(radius: bulletRadius))
        bullet.model?.materials = [SimpleMaterial(color: .green, isMetallic: true)]
        
        self.addChild(bullet)
        self.generateCollisionShapes(recursive: true)
        
        self.anchoring = AnchoringComponent(.world(transform: self.transform.matrix))
    }
}

class MonsterSpawner {
    private var arView: ARView
    private var monsters: [MonsterEntity] = []
    private var monsterAnchors: [AnchorEntity] = []
    private weak var coordinator: ARViewContainer.Coordinator?

    init(arView: ARView, coordinator: ARViewContainer.Coordinator) {
        self.arView = arView
        self.coordinator = coordinator
    }

    func spawnMonster() async {
        guard let coordinator = coordinator else {
            print("⚠️ Error: Coordinator is nil, cannot spawn monster.")
            return
        }

        let monster = await MonsterEntity(named: "Green_Dragon", coordinator: coordinator)
        monster.coordinator = coordinator

        monster.onMonsterDeath = { [weak self] in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                print("Monster defeated! Removing from scene and updating score.")

                coordinator.parent.score += 100
                print("New score:", coordinator.parent.score)

                // Remove the monster's anchor from the scene
                if let index = self.monsters.firstIndex(where: { $0 === monster }) {
                    let anchor = self.monsterAnchors[index]
                    self.arView.scene.anchors.remove(anchor)
                    self.monsters.remove(at: index)
                    self.monsterAnchors.remove(at: index)
                }
                
                self.spawnNewMonsterAfterDelay()
            }
        }

        let randomAngle = Float.random(in: 0...(2 * .pi))
        let randomDistance = Float.random(in: 2...5)
        let x = randomDistance * cos(randomAngle)
        let z = randomDistance * sin(randomAngle)

        await MainActor.run {
            monster.position = SIMD3<Float>(x, 0.5, z)

            let playerPosition = SIMD3<Float>(0, 0.5, 0)
            let directionToPlayer = normalize(playerPosition - monster.position)

            let forward = normalize(directionToPlayer)
            let up = SIMD3<Float>(0, 1, 0)
            let right = normalize(cross(up, forward))
            let adjustedUp = cross(forward, right)

            let rotationMatrix = float3x3(right, adjustedUp, forward)
            let rotationQuaternion = simd_quatf(rotationMatrix)
            monster.transform.rotation = rotationQuaternion

            let anchorEntity = AnchorEntity(world: monster.position)
            anchorEntity.addChild(monster)
            self.arView.scene.addAnchor(anchorEntity)
            self.monsters.append(monster)
            self.monsterAnchors.append(anchorEntity)
        }

        if let playerEntity = arView.scene.anchors.first {
            monster.startShooting(at: playerEntity, in: arView)
        }
    }

    private func spawnNewMonsterAfterDelay() {
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await spawnMonster()
        }
    }

    func removeAllMonsters() {
        DispatchQueue.main.async {
            for (index, _) in self.monsters.enumerated() {
                let anchor = self.monsterAnchors[index]
                self.arView.scene.anchors.remove(anchor)
            }
            self.monsters.removeAll()
            self.monsterAnchors.removeAll()
        }
    }
}
