/**
 * Feature toggles entregues ao app por `GET /users/me/features`.
 *
 * Hoje só controlam a monetização por anúncios, mas a decisão já recebe o `plano` do usuário:
 * quando existir um plano pago, basta incluí-lo em `ADS_FREE_PLANS` (ou mudar a regra aqui) para
 * que quem assina deixe de ver anúncios — sem publicar uma nova versão do app.
 *
 * Tudo é lido de variáveis de ambiente para que ligar/desligar anúncios (ou um formato específico)
 * seja só editar o `.env` e reiniciar a API.
 */
export interface AdsFeatureFlags {
  /** Chave-mestra: `false` desliga todos os formatos abaixo. */
  enabled: boolean;
  banner: boolean;
  interstitial: boolean;
  rewarded: boolean;
  /** Frequency capping do intersticial: intervalo mínimo entre duas exibições. */
  interstitialMinIntervalSeconds: number;
  /** Por quanto tempo o desbloqueio ganho com um anúncio premiado vale. */
  rewardedUnlockMinutes: number;
}

export interface FeatureFlags {
  plano: string;
  ads: AdsFeatureFlags;
  limits: {
    /** Sincronizações manuais por dia no plano gratuito. `null` = ilimitado. */
    manualSyncsPerDay: number | null;
  };
}

type Env = Record<string, string | undefined>;

function readBool(env: Env, key: string, fallback: boolean): boolean {
  const raw = env[key]?.trim().toLowerCase();
  if (raw === undefined || raw === '') return fallback;
  return raw === 'true' || raw === '1';
}

function readPositiveInt(
  env: Env,
  key: string,
  fallback: number | null,
): number | null {
  const raw = env[key]?.trim();
  if (raw === undefined || raw === '') return fallback;
  const value = Number(raw);
  return Number.isInteger(value) && value > 0 ? value : fallback;
}

export function resolveFeatureFlags(
  plano: string,
  env: Env = process.env,
): FeatureFlags {
  const adsFreePlans = (env.ADS_FREE_PLANS ?? 'pro')
    .split(',')
    .map((p) => p.trim())
    .filter((p) => p.length > 0);
  const planoSemAnuncios = adsFreePlans.includes(plano);

  // Desligado por padrão: anúncios só aparecem quando alguém liga explicitamente no ambiente.
  const enabled = readBool(env, 'ADS_ENABLED', false) && !planoSemAnuncios;

  return {
    plano,
    ads: {
      enabled,
      banner: enabled && readBool(env, 'ADS_BANNER_ENABLED', true),
      interstitial: enabled && readBool(env, 'ADS_INTERSTITIAL_ENABLED', true),
      rewarded: enabled && readBool(env, 'ADS_REWARDED_ENABLED', true),
      interstitialMinIntervalSeconds: readPositiveInt(
        env,
        'ADS_INTERSTITIAL_MIN_INTERVAL_SECONDS',
        180,
      )!,
      rewardedUnlockMinutes: readPositiveInt(
        env,
        'ADS_REWARDED_UNLOCK_MINUTES',
        60,
      )!,
    },
    limits: {
      // Planos sem anúncios (pagos) nunca têm limite; no gratuito o limite só existe se configurado.
      manualSyncsPerDay: planoSemAnuncios
        ? null
        : readPositiveInt(env, 'FREE_MANUAL_SYNCS_PER_DAY', null),
    },
  };
}
