import Foundation
import Network

/// Quick health check for the coordinator HTTP server.
enum CoordinatorHealthCheck {
    static func check(host: String, port: UInt16 = TestReceiverConfig.coordinatorPort) async -> Bool {
        guard let url = URL(string: "http://\(host):\(port)/health") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 2
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return false }
            return (try? JSONDecoder().decode(ARCPHealthResponse.self, from: data))?.ok == true
        } catch {
            return false
        }
    }
}
