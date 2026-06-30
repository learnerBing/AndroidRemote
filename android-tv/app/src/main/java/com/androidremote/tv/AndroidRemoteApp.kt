package com.androidremote.tv

import android.app.Application
import com.androidremote.tv.di.AppContainer

class AndroidRemoteApp : Application() {

    lateinit var container: AppContainer
        private set

    override fun onCreate() {
        super.onCreate()
        container = AppContainer(this)
    }

    companion object {
        fun container(app: Application): AppContainer =
            (app as AndroidRemoteApp).container
    }
}
