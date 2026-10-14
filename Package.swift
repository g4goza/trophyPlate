// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "TrophyPlate", platforms: [.macOS(.v14)],
    products: [.library(name: "TrophyPlateCore", targets: ["TrophyPlateCore"]), .executable(name: "TrophyPlate", targets: ["TrophyPlate"])],
    targets: [.target(name: "TrophyPlateCore"), .executableTarget(name: "TrophyPlate", dependencies: ["TrophyPlateCore"]), .testTarget(name: "TrophyPlateCoreTests", dependencies: ["TrophyPlateCore"]), .testTarget(name: "TrophyPlateAppTests", dependencies: ["TrophyPlate", "TrophyPlateCore"])])
