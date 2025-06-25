import Foundation
import RemoteAnisette

extension AnisetteUser {
    init(file: URL) throws { self = try JSONDecoder().decode(Self.self, from: try Data(contentsOf: file)) }
    
    func write(to file: URL) {
        do { try JSONEncoder().encode(self).write(to: file) }
        catch { print("Failed to write ani.conf: \(error)") }
    }
}

@main
struct GetRemoteAnisette {
    static func main() async throws {
        let confPath: URL = URL(fileURLWithPath: CommandLine.argc > 1 ? CommandLine.arguments[1] : "/dev/null")
        if let u = try? AnisetteUser(file: confPath) {
            print(try await u.fetchHeaders())
        } else {
            var u = AnisetteUser()
            do {
                try await u.provision()
            } catch { if (error as NSError).code != 57 { print(error) } }
            guard u.adiPB != nil else { return print("Something went wrong, nil adi.pb O_o") }
            if confPath.path != "/dev/null" {
                print("provisioned adi.pb, saving to \(confPath)")
                u.write(to: confPath)
            }
            print(try await u.fetchHeaders())
        }
    }
}
