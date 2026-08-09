import 'dotenv/config';
import { NestFactory } from '@nestjs/core';
import { ValidationPipe } from '@nestjs/common';
import { AppModule } from './app.module';

async function bootstrap() {
  const app = await NestFactory.create(AppModule, { rawBody: true });
  // Native mobile clients (Android/iOS) don't send an Origin header, so CORS never applied to
  // them — this was only ever missing for the mobile-web build, which runs in an actual browser
  // and authenticates via a Bearer token (no cookies), so a permissive origin carries no
  // credential-leak risk.
  app.enableCors();
  app.useGlobalPipes(new ValidationPipe({ whitelist: true, forbidNonWhitelisted: true }));
  await app.listen(process.env.PORT ?? 3000);
}
bootstrap();
