package com.androidremote.tv.data.discovery

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.util.Log

class MdnsAdvertiser(
    private val context: Context,
    private val servicePort: Int = 8765
) {
    private val nsdManager = context.getSystemService(Context.NSD_SERVICE) as NsdManager
    private var registrationListener: NsdManager.RegistrationListener? = null

    fun start(deviceName: String) {
        stop()

        val serviceInfo = NsdServiceInfo().apply {
            serviceName = sanitizeName(deviceName)
            serviceType = SERVICE_TYPE
            port = servicePort
        }

        registrationListener = object : NsdManager.RegistrationListener {
            override fun onServiceRegistered(info: NsdServiceInfo) {
                Log.i(TAG, "mDNS registered: ${info.serviceName}")
            }

            override fun onRegistrationFailed(info: NsdServiceInfo, errorCode: Int) {
                Log.e(TAG, "mDNS registration failed: $errorCode")
            }

            override fun onServiceUnregistered(info: NsdServiceInfo) = Unit
            override fun onUnregistrationFailed(info: NsdServiceInfo, errorCode: Int) = Unit
        }

        nsdManager.registerService(serviceInfo, NsdManager.PROTOCOL_DNS_SD, registrationListener)
    }

    fun stop() {
        registrationListener?.let {
            try {
                nsdManager.unregisterService(it)
            } catch (_: Exception) {
                // Already unregistered
            }
        }
        registrationListener = null
    }

    private fun sanitizeName(name: String): String =
        name.filter { it.isLetterOrDigit() || it == '-' || it == '_' }
            .take(63)
            .ifEmpty { "AndroidRemoteTV" }

    companion object {
        const val SERVICE_TYPE = "_androidremote._tcp."
        private const val TAG = "MdnsAdvertiser"
    }
}
