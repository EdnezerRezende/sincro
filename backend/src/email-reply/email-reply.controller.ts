import {
  Body,
  Controller,
  ForbiddenException,
  Logger,
  Param,
  Post,
  ServiceUnavailableException,
  UseGuards,
} from '@nestjs/common';
import { FirebaseAuthGuard } from '../auth/firebase-auth.guard';
import { CurrentFirebaseUid } from '../common/current-firebase-uid.decorator';
import { UsersService } from '../users/users.service';
import { GmailConnectionsService } from '../gmail/gmail-connections.service';
import { GmailApiClient } from '../gmail/gmail-api-client.service';
import { mapearErroGmail } from '../gmail/gmail-error.util';
import { CalendarApiClient } from '../calendar/calendar-api-client.service';
import { EmailSyncService } from '../email-sync/email-sync.service';
import { EmailDraftService } from './email-draft.service';
import { EmailCommitmentExtractionService } from './email-commitment-extraction.service';
import { EnviarRespostaDto } from './dto/enviar-resposta.dto';
import { ConfirmarCompromissoDto } from './dto/confirmar-compromisso.dto';

@UseGuards(FirebaseAuthGuard)
@Controller('resumos-email')
export class EmailReplyController {
  private readonly logger = new Logger(EmailReplyController.name);

  constructor(
    private readonly usersService: UsersService,
    private readonly emailSyncService: EmailSyncService,
    private readonly connectionsService: GmailConnectionsService,
    private readonly gmailApiClient: GmailApiClient,
    private readonly calendarApiClient: CalendarApiClient,
    private readonly draftService: EmailDraftService,
    private readonly extractionService: EmailCommitmentExtractionService,
  ) {}

  @Post(':id/rascunhos')
  async gerarRascunhos(@CurrentFirebaseUid() firebaseUid: string, @Param('id') id: string) {
    const summary = await this.emailSyncService.getOwned(firebaseUid, id);
    const user = await this.usersService.getByFirebaseUidOrThrow(firebaseUid);
    const connection = await this.connectionsService.getConnectionOrThrow(user.id);
    if (!connection.temEscopoEnvio) {
      throw new ForbiddenException('Reconecte o Gmail para responder por aqui.');
    }
    const refreshToken = await this.connectionsService.getDecryptedRefreshToken(user.id);
    // A falha aqui (token revogado, e-mail apagado direto no Gmail, Gmail indisponível) vira uma
    // resposta HTTP honesta via `mapearErroGmail`, nunca um 500 cru — o mesmo tratamento já usado
    // em `GET /:id/conteudo`. Este `catch` é só sobre a chamada ao Gmail: a chamada à IA logo
    // abaixo tem o SEU PRÓPRIO `try/catch`, que não pode ser fundido com este (o 503 dela é sobre a
    // IA estar indisponível, não sobre o Gmail).
    let corpo: string;
    try {
      ({ texto: corpo } = await this.gmailApiClient.fetchFullBody(refreshToken as string, summary.gmailMessageId));
    } catch (error) {
      throw mapearErroGmail(error, 'Este e-mail não existe mais no Gmail — ele pode ter sido apagado por lá.');
    }
    // Reading the e-mail (GET /:id/conteudo) never depends on this call, so it's now safe for a
    // failure here (Anthropic account out of credits, malformed model output, network hiccup) to
    // become an honest, handled HTTP response instead of an unhandled 500 — the mobile client
    // shows a calm, local retry affordance next to the (already visible) e-mail body.
    try {
      return await this.draftService.gerar({ remetente: summary.remetente, assunto: summary.assunto, corpo });
    } catch (error) {
      this.logger.warn(`Draft generation failed for e-mail ${id}: ${error}`);
      throw new ServiceUnavailableException('Sugestão de resposta indisponível no momento. Tente novamente mais tarde.');
    }
  }

  @Post(':id/enviar')
  async enviar(
    @CurrentFirebaseUid() firebaseUid: string,
    @Param('id') id: string,
    @Body() dto: EnviarRespostaDto,
  ) {
    const summary = await this.emailSyncService.getOwned(firebaseUid, id);
    const user = await this.usersService.getByFirebaseUidOrThrow(firebaseUid);
    const connection = await this.connectionsService.getConnectionOrThrow(user.id);
    if (!connection.temEscopoEnvio) {
      throw new ForbiddenException('Reconecte o Gmail para responder por aqui.');
    }
    const refreshToken = await this.connectionsService.getDecryptedRefreshToken(user.id);
    try {
      await this.gmailApiClient.sendReply(refreshToken as string, {
        gmailMessageId: summary.gmailMessageId,
        para: summary.remetente,
        assunto: summary.assunto,
        texto: dto.texto,
      });
    } catch (error) {
      throw mapearErroGmail(error, 'Este e-mail não existe mais no Gmail — ele pode ter sido apagado por lá.');
    }

    // `extractionService.extrair` nunca lança (ver seu próprio comentário): uma falha na IA aqui
    // nunca pode desfazer um envio que já aconteceu de verdade.
    const compromissoSugerido = await this.extractionService.extrair(dto.texto);
    return { enviado: true, compromissoSugerido };
  }

  @Post('compromissos/confirmar')
  async confirmarCompromisso(@CurrentFirebaseUid() firebaseUid: string, @Body() dto: ConfirmarCompromissoDto) {
    const user = await this.usersService.getByFirebaseUidOrThrow(firebaseUid);
    const connection = await this.connectionsService.getConnectionOrThrow(user.id);
    if (!connection.temEscopoAgenda) {
      throw new ForbiddenException('Reconecte o Gmail para usar a agenda.');
    }
    const refreshToken = await this.connectionsService.getDecryptedRefreshToken(user.id);
    try {
      await this.calendarApiClient.criarEvento(refreshToken as string, dto);
    } catch (error) {
      throw mapearErroGmail(error);
    }
    return { agendado: true };
  }
}
