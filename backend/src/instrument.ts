import * as Sentry from '@sentry/nestjs';

// SENTRY_DSN vazio/ausente é um estado válido (dev local, ou a VPS antes do secret ser
// configurado) — Sentry.init com dsn undefined vira um no-op silencioso, então não há guard
// condicional aqui de propósito. Este ambiente é só error tracking (sem tracing/profiling) —
// ver Global Constraints do plano: observabilidade desta fase é só rastreamento de erros.
Sentry.init({
  dsn: process.env.SENTRY_DSN,
  environment: process.env.NODE_ENV ?? 'development',
});
