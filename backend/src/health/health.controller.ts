import { Controller, Get, ServiceUnavailableException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';

/**
 * Verificação de saúde pública (sem autenticação), usada pelo deploy automático para confirmar
 * que a API subiu depois de um `docker compose up` e por monitores de disponibilidade.
 * Responde 503 quando o banco não responde, para o deploy não reportar sucesso com a API sem banco.
 */
@Controller('health')
export class HealthController {
  constructor(private readonly prisma: PrismaService) {}

  @Get()
  async check(): Promise<{ status: 'ok' }> {
    try {
      await this.prisma.$queryRaw`SELECT 1`;
    } catch {
      throw new ServiceUnavailableException({
        status: 'error',
        database: 'unreachable',
      });
    }
    return { status: 'ok' };
  }
}
