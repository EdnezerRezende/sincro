import { Module, OnModuleInit, Logger } from '@nestjs/common';
import { WhatsappWebhookController } from './whatsapp-webhook.controller';
import { MetaCloudParser } from './providers/meta-cloud.parser';
import { PrismaService } from '../prisma/prisma.service';

@Module({
  imports: [],
  controllers: [WhatsappWebhookController],
  providers: [MetaCloudParser, PrismaService],
  exports: [MetaCloudParser],
})
export class WhatsappModule implements OnModuleInit {
  private readonly logger = new Logger(WhatsappModule.name);

  onModuleInit() {
    // Validar variáveis de ambiente obrigatórias
    const required = [
      'WHATSAPP_APP_SECRET',
      'WHATSAPP_VERIFY_TOKEN',
      'WHATSAPP_PHONE_NUMBER_ID',
      'WHATSAPP_ACCESS_TOKEN',
      'WHATSAPP_HASH_PEPPER',
    ];

    const missing = required.filter((v) => !process.env[v]);
    if (missing.length > 0) {
      this.logger.error(
        `WhatsappModule: variáveis obrigatórias não configuradas: ${missing.join(', ')}`,
      );
      this.logger.warn('WhatsappModule: webhook responderá com 503 até configuração completa');
      // Não lança erro aqui: deixa o resto da API subir, webhook fica inoperante
    } else {
      this.logger.log('WhatsappModule: variáveis de ambiente validadas ✓');
    }
  }
}
