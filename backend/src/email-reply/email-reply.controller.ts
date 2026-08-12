import { Body, Controller, ForbiddenException, Param, Post, UseGuards } from '@nestjs/common';
import { FirebaseAuthGuard } from '../auth/firebase-auth.guard';
import { CurrentFirebaseUid } from '../common/current-firebase-uid.decorator';
import { UsersService } from '../users/users.service';
import { GmailConnectionsService } from '../gmail/gmail-connections.service';
import { GmailApiClient } from '../gmail/gmail-api-client.service';
import { CalendarApiClient } from '../calendar/calendar-api-client.service';
import { EmailSyncService } from '../email-sync/email-sync.service';
import { EmailDraftService } from './email-draft.service';
import { EmailCommitmentExtractionService } from './email-commitment-extraction.service';
import { EnviarRespostaDto } from './dto/enviar-resposta.dto';
import { ConfirmarCompromissoDto } from './dto/confirmar-compromisso.dto';

@UseGuards(FirebaseAuthGuard)
@Controller('resumos-email')
export class EmailReplyController {
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
    const corpo = await this.gmailApiClient.fetchFullBody(refreshToken as string, summary.gmailMessageId);
    return this.draftService.gerar({ remetente: summary.remetente, assunto: summary.assunto, corpo });
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
    await this.gmailApiClient.sendReply(refreshToken as string, {
      gmailMessageId: summary.gmailMessageId,
      para: summary.remetente,
      assunto: summary.assunto,
      texto: dto.texto,
    });

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
    await this.calendarApiClient.criarEvento(refreshToken as string, dto);
    return { agendado: true };
  }
}
