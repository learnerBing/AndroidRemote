import Foundation

// MARK: - V2 Repository Protocols (stubs — implement in V2)

protocol MediaCastRepository {
    func switchMode(_ mode: CastMode, sessionId: String) async throws
    func uploadPhotos(sessionId: String, assets: [String]) async throws
    func castVideo(sessionId: String, item: MediaItem) async throws
    func syncIptvPlaylist(sessionId: String, playlist: IptvPlaylist) async throws
    func castYoutube(sessionId: String, request: YoutubeCastRequest) async throws
}

protocol RemoteControlRepository {
    func send(command: RemoteCommand) async throws
    var isConnected: Bool { get }
}
