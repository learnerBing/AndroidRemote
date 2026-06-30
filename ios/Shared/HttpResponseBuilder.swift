import Foundation

/// Shared minimal HTTP helpers for LAN signaling servers (main app + broadcast extension).
enum HttpResponseBuilder {
    static func parseQuery(_ pathAndQuery: String) -> [String: String] {
        guard let queryStart = pathAndQuery.firstIndex(of: "?") else { return [:] }
        let query = pathAndQuery[pathAndQuery.index(after: queryStart)...]
        var result: [String: String] = [:]
        for pair in query.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1)
            if kv.count == 2 {
                result[String(kv[0])] = String(kv[1]).removingPercentEncoding ?? String(kv[1])
            }
        }
        return result
    }

    static func json<T: Encodable>(_ value: T, cors: Bool = false) -> String {
        let data = (try? JSONEncoder().encode(value)) ?? Data("{}".utf8)
        let body = String(data: data, encoding: .utf8) ?? "{}"
        return response(status: 200, body: body, contentType: "application/json", cors: cors)
    }

    static func response(status: Int, body: String, contentType: String, cors: Bool = false) -> String {
        let statusText: String
        switch status {
        case 200: statusText = "OK"
        case 204: statusText = "No Content"
        case 400: statusText = "Bad Request"
        case 404: statusText = "Not Found"
        default: statusText = "Error"
        }
        let corsHeaders = cors
            ? "Access-Control-Allow-Origin: *\r\nAccess-Control-Allow-Methods: GET, POST, OPTIONS\r\nAccess-Control-Allow-Headers: Content-Type\r\n"
            : ""
        return """
        HTTP/1.1 \(status) \(statusText)\r
        Content-Type: \(contentType)\r
        Content-Length: \(body.utf8.count)\r
        \(corsHeaders)Connection: close\r
        \r
        \(body)
        """
    }
}
