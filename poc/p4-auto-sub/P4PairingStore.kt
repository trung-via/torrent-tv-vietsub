// SPDX-License-Identifier: GPL-3.0-only
package com.spacesarmat.omp.player

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * One-time PC pairing stored in private Android app data, encrypted with
 * a non-exportable AndroidKeyStore AES-GCM key. Never in logs/intents/URLs.
 * A user-visible opt-in is required for every new film.
 */
internal class P4PairingStore(ctx: Context) {
    private val prefs=ctx.getSharedPreferences("p4-tv-paired-pc-v1",Context.MODE_PRIVATE)
    internal data class Pairing(val host:String,val port:Int,val deviceSecret:ByteArray)

    fun save(host:String,port:Int,deviceSecret:ByteArray):Boolean {
        if (deviceSecret.size!=32) return false
        try { P4LanClient.activationEndpoint(host,port) }
        catch (_: Exception) { return false }
        return try {
            val cipher=Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.ENCRYPT_MODE,masterKey())
            val iv=Base64.encodeToString(cipher.iv,Base64.NO_WRAP)
            val encrypted=Base64.encodeToString(cipher.doFinal(deviceSecret),Base64.NO_WRAP)
            prefs.edit().putString("host",host).putInt("port",port)
                .putString("iv",iv).putString("sealed",encrypted).commit()
        } catch (_: Exception) { false }
    }

    fun load():Pairing? {
        val host=prefs.getString("host",null) ?: return null
        val port=prefs.getInt("port",0)
        try { P4LanClient.activationEndpoint(host,port) }
        catch (_: Exception) { return null }
        return try {
            val iv=Base64.decode(prefs.getString("iv",null) ?: return null,Base64.NO_WRAP)
            val encrypted=Base64.decode(
                prefs.getString("sealed",null) ?: return null,Base64.NO_WRAP)
            if (iv.size!=12 || encrypted.size !in 48..128) return null
            val cipher=Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE,masterKey(),GCMParameterSpec(128,iv))
            val secret=cipher.doFinal(encrypted)
            if (secret.size!=32) { secret.fill(0); return null }
            Pairing(host,port,secret)
        } catch (_: Exception) { null }
    }

    fun revoke():Boolean = prefs.edit().clear().commit()

    private fun masterKey():SecretKey {
        val store=KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        val existing=store.getKey(ALIAS,null) as? SecretKey
        if (existing!=null) return existing
        val gen=KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES,"AndroidKeyStore")
        gen.init(KeyGenParameterSpec.Builder(
            ALIAS,KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256).build())
        return gen.generateKey()
    }

    companion object {
        private const val ALIAS="torrent-tv-p4-paired-pc-v1"
    }
}
