// swift-tools-version: 5.9
/**
 X-Apple-Client-Time - Client time
 X-Apple-I-MD        - One Time Password
 X-Apple-I-MD-LU     - Local user ID
 X-Apple-I-MD-M      - Machine ID
 X-Apple-I-MD-RINFO  - Routing info
 X-Apple-I-SRL-NO    - Serial number
 X-Apple-I-TimeZone  - Timezone
 X-Apple-Locale      - Locale
 X-Mme-Drvice-Id     - Device unique identifier
 
 X-MMe-Client-Info   - Application/client info
 */

import PackageDescription

let package = Package(
    name: "RemoteAnisette",
    platforms: [.macOS(.v10_15), .iOS(.v13), .watchOS(.v8), .tvOS(.v13), .visionOS(.v1)],
    products: [
        .executable(name: "GetRemoteAnisette", targets: ["GetRemoteAnisette"]),
        .library(name: "RemoteAnisette", targets: ["RemoteAnisette"]),
    ],
    dependencies: [
        .package(url: "https://github.com/tayloraswift/swift-hash.git", from: "0.7.1"),
    ],
    targets: [
        .executableTarget(name: "GetRemoteAnisette", dependencies: ["RemoteAnisette"]),
        .target(name: "RemoteAnisette", dependencies: [.product(name: "SHA2", package: "swift-hash")]),
        .testTarget(name: "RemoteAnisetteTests", dependencies: ["RemoteAnisette"]
        ),
    ]
)
