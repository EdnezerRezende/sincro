package com.sincro.sincro_mobile

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Bundle

// Aberta pelo Health Connect quando o usuário toca em "política de privacidade" na tela de
// permissões de saúde (exigência do Health Connect e da Play). Só repassa para o navegador.
class PrivacyPolicyActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        try {
            startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(PRIVACY_POLICY_URL)))
        } catch (_: ActivityNotFoundException) {
            // Sem navegador instalado: não há o que abrir; só fecha.
        }
        finish()
    }

    companion object {
        // Trocar junto com o domínio de produção (checklist, seção 7).
        const val PRIVACY_POLICY_URL = "https://sincro-sandbox.duckdns.org/privacidade.html"
    }
}
