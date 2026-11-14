// SPDX-License-Identifier: GPL-3.0-only
package com.spacesarmat.omp.player

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import java.security.KeyStore

/**
 * Device-level PC pairing: a 256-bit HMAC key and the PC TLS certificate pin
 * are BOTH sealed under app-private AndroidKeyStore AES-256-GCM. Legacy HTTP
 * credentials are not migrated; HTTPS requires explicit, new provisioning.
 */
internal class P4PairingStore(ctx: Context) {
    private val prefs=ctx.getSharedPreferences("p4-tv-paired-pc-v2-tls",Context.MODE_PRIVATE)
    internal data class Pairing(
        val host:String,val port:Int,val deviceSecret:ByteArray,val certPinSha256:String,
    )

    fun save(host:String,port:Int,deviceSecret:ByteArray,certPinSha256:String):Boolean {
        if (deviceSecret.size != 32) return false
        try { P4LanClient.activationEndpoint(host,port) }
        catch (_: Exception) { return false }
        val pin = try { P4PinnedTls.normalizePin(certPinSha256) }
                  catch (_: Exception) { return false }
        val pinBytes = ByteArray(32) { i ->
            pin.substring(i*2,i*2+2).toInt(16).toByte()
        }
        val plain = deviceSecret + pinBytes
        return try {
            val cipher=Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.ENCRYPT_MODE,masterKey())
            val iv=Base64.encodeToString(cipher.iv,Base64.NO_WRAP)
            val encrypted=Base64.encodeToString(cipher.doFinal(plain),Base64.NO_WRAP)
            prefs.edit().putString("host",host).putInt("port",port)
                .putString("iv",iv).putString("sealed",encrypted).commit()
        } catch (_: Exception) { false }
        finally {
            pinBytes.fill(0)
            plain.fill(0)
        }
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
            if (iv.size!=12 || encrypted.size!=80) return null
            val cipher=Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE,masterKey(),GCMParameterSpec(128,iv))
            val plain=cipher.doFinal(encrypted)
            try {
                if (plain.size!=64) return null
                val secret=plain.copyOfRange(0,32)
                val pin=plain.copyOfRange(32,64).joinToString("") {
                    "%02x".format(it.toInt() and 255)
                }
                Pairing(host,port,secret,P4PinnedTls.normalizePin(pin))
            } finally { plain.fill(0) }
        } catch (_: Exception) { null }
    }

    fun revoke():Boolean {
        val cleared=prefs.edit().clear().commit()
        if (!cleared) return false
        return try {
            KeyStore.getInstance("AndroidKeyStore").apply { load(null) }.deleteEntry(ALIAS)
            true
        } catch (_: Exception) { false }
    }

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
        private const val ALIAS="torrent-tv-p4-paired-pc-v2-tls"
    }
}
