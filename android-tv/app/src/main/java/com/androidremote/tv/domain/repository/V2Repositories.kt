package com.androidremote.tv.domain.repository

import com.androidremote.tv.domain.model.CastMode
import com.androidremote.tv.domain.model.IptvPlaylist
import com.androidremote.tv.domain.model.MediaItem
import com.androidremote.tv.domain.model.RemoteCommand
import com.androidremote.tv.domain.model.YoutubeCastRequest

/** V2 repository protocols — implemented in Phase 5+. */
interface MediaCastRepository {
    suspend fun switchMode(mode: CastMode, sessionId: String)
    suspend fun displayPhoto(sessionId: String, imageBytes: ByteArray, mimeType: String)
    suspend fun playMedia(sessionId: String, item: MediaItem)
    suspend fun syncIptvPlaylist(sessionId: String, playlist: IptvPlaylist)
    suspend fun playYoutube(sessionId: String, request: YoutubeCastRequest)
}

interface RemoteControlRepository {
    suspend fun handle(command: RemoteCommand)
}

interface CastModeRouter {
    val activeMode: CastMode
    suspend fun route(mode: CastMode, sessionId: String)
}
