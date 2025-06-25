import Foundation
import Testing
@testable import RemoteAnisette

@Test func example() async throws {
    // Write your test here and use APIs like `#expect(...)` to check expected conditions.
    let ani = RemoteAnisetteManager(url: URL(string: "https://ani.sidestore.io")!)
    let cInfo = try await ani.fetchClientInfo()
    let user = AnisetteUser(client: cInfo)
    print(user)
    try await ani.fetchProvisioningURLs(user: user)
}
