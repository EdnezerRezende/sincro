import * as Sentry from '@sentry/nestjs';
import { nodeProfilingIntegration } from '@sentry/profiling-node';

// SENTRY_DSN vazio/ausente é um estado válido (dev local, ou a VPS antes do secret ser
// configurado) — Sentry.init com dsn undefined vira um no-op silencioso, então não há guard
// condicional aqui de propósito.
Sentry.init({
  dsn: process.env.SENTRY_DSN,
  environment: process.env.NODE_ENV ?? 'development',
  integrations: [nodeProfilingIntegration()],
  tracesSampleRate: 1.0,
  profilesSampleRate: 1.0,
});
