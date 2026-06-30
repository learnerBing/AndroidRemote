import Foundation

// MARK: - V2 Cast Modes

/// What the user is casting. V1 implements `.screen` only.
enum CastMode: String, CaseIterable, Identifiable {
    case screen
    case photo
    case video
    case iptv
    case youtube
    case remote

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .screen: return "Mirror"
        case .photo: return "Photos"
        case .video: return "Videos"
        case .iptv: return "IPTV"
        case .youtube: return "YouTube"
        case .remote: return "Remote"
        }
    }

    var systemImage: String {
        switch self {
        case .screen: return "rectangle.on.rectangle"
        case .photo: return "photo.on.rectangle"
        case .video: return "play.rectangle"
        case .iptv: return "tv"
        case .youtube: return "play.circle"
        case .remote: return "appletvremote.gen4"
        }
    }

    var isV1: Bool { self == .screen }
}

// MARK: - V2 Media

struct MediaItem: Identifiable, Equatable {
    let id: String
    let title: String
    let sourceUrl: URL
    let mimeType: String
    let thumbnailUrl: URL?
}

struct IptvChannel: Identifiable, Equatable {
    let id: String
    let name: String
    let group: String
    let streamUrl: URL
    let logoUrl: URL?
}

struct IptvPlaylist: Equatable {
    var name: String
    var channels: [IptvChannel]
    var epgUrl: URL?
}

struct YoutubeCastRequest: Equatable {
    let videoId: String
    let url: URL
}

// MARK: - V2 Remote

enum RemoteKey: String, CaseIterable {
    case dpadUp = "DPAD_UP"
    case dpadDown = "DPAD_DOWN"
    case dpadLeft = "DPAD_LEFT"
    case dpadRight = "DPAD_RIGHT"
    case enter = "ENTER"
    case back = "BACK"
    case home = "HOME"
    case play = "PLAY"
    case pause = "PAUSE"
    case playPause = "PLAY_PAUSE"
    case volumeUp = "VOLUME_UP"
    case volumeDown = "VOLUME_DOWN"
}

struct RemoteCommand: Equatable {
    let sessionId: String
    let key: RemoteKey
    let timestamp: Date
}
