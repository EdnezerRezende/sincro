import { resolveFeatureFlags } from './feature-flags';

describe('resolveFeatureFlags', () => {
  it('keeps every ad format off when ADS_ENABLED is not set', () => {
    const flags = resolveFeatureFlags('simples', {});

    expect(flags.ads).toEqual({
      enabled: false,
      banner: false,
      interstitial: false,
      rewarded: false,
      interstitialMinIntervalSeconds: 180,
      rewardedUnlockMinutes: 60,
    });
    expect(flags.limits.manualSyncsPerDay).toBeNull();
  });

  it('turns on all formats for the free plan when the master switch is on', () => {
    const flags = resolveFeatureFlags('simples', { ADS_ENABLED: 'true' });

    expect(flags.ads.enabled).toBe(true);
    expect(flags.ads.banner).toBe(true);
    expect(flags.ads.interstitial).toBe(true);
    expect(flags.ads.rewarded).toBe(true);
  });

  it('allows toggling a single format off', () => {
    const flags = resolveFeatureFlags('simples', {
      ADS_ENABLED: 'true',
      ADS_BANNER_ENABLED: 'false',
    });

    expect(flags.ads.banner).toBe(false);
    expect(flags.ads.interstitial).toBe(true);
  });

  it('never shows ads nor limits syncs for ad-free plans', () => {
    const env = { ADS_ENABLED: 'true', FREE_MANUAL_SYNCS_PER_DAY: '3' };

    const pro = resolveFeatureFlags('pro', env);
    expect(pro.ads.enabled).toBe(false);
    expect(pro.ads.banner).toBe(false);
    expect(pro.limits.manualSyncsPerDay).toBeNull();

    expect(resolveFeatureFlags('simples', env).limits.manualSyncsPerDay).toBe(
      3,
    );
  });

  it('honours a custom list of ad-free plans', () => {
    const env = { ADS_ENABLED: 'true', ADS_FREE_PLANS: 'premium, familia' };

    expect(resolveFeatureFlags('familia', env).ads.enabled).toBe(false);
    expect(resolveFeatureFlags('pro', env).ads.enabled).toBe(true);
  });

  it('falls back to defaults on invalid numbers', () => {
    const flags = resolveFeatureFlags('simples', {
      ADS_INTERSTITIAL_MIN_INTERVAL_SECONDS: 'abc',
      ADS_REWARDED_UNLOCK_MINUTES: '-5',
    });

    expect(flags.ads.interstitialMinIntervalSeconds).toBe(180);
    expect(flags.ads.rewardedUnlockMinutes).toBe(60);
  });
});
