import { Controller, ForbiddenException, Get, Param, Post, UseGuards } from '@nestjs/common';
import { FirebaseAuthGuard } from '../auth/firebase-auth.guard';
import { CurrentFirebaseUid } from '../common/current-firebase-uid.decorator';
import { UsersService } from '../users/users.service';
import { GmailConnectionsService } from '../gmail/gmail-connections.service';
import { GmailApiClient } from '../gmail/gmail-api-client.service';
import { gmailMensagemNaoEncontrada, mapearErroGmail } from '../gmail/gmail-error.util';
import { EmailSyncService } from './email-sync.service';

@UseGuards(FirebaseAuthGuard)
@Controller('resumos-email')
export class EmailSummaryController {
  constructor(
    private readonly emailSyncService: EmailSyncService,
    private readonly usersService: UsersService,
    private readonly connectionsService: GmailConnectionsService,
    private readonly gmailApiClient: GmailApiClient,
  ) {}

  @Get()
  async list(@CurrentFirebaseUid() firebaseUid: string) {
    return this.emailSyncService.list(firebaseUid);
  }

  /** Full body for READING the e-mail — no LLM involved, so it never fails because a third-party
   *  AI provider is down or out of credits. Fetched on demand from Gmail rather than persisted in
   *  `resumos_email` (which today only stores the derived summary): the body is the most sensitive
   *  content the app touches, and there's no reason to hold a second copy of it at rest when the
   *  Gmail API is already fast enough to read it live on open. Only requires that a Gmail
   *  connection exists — unlike drafting/sending, reading never touches gmail.send scope.
   *
   *  `ehPreview: true` means `fetchFullBody` couldn't build readable text from the message (no
   *  `text/plain`, no `text/html` either) and fell back to Gmail's own short snippet — the client
   *  is expected to say so, not present that snippet as if it were the whole message.
   *
   *  A failed Gmail call here (revoked token, message deleted straight from Gmail, Gmail itself
   *  down) is mapped to an honest HTTP response by `mapearErroGmail` instead of bubbling up as an
   *  unhandled 500. */
  @Get(':id/conteudo')
  async conteudo(@CurrentFirebaseUid() firebaseUid: string, @Param('id') id: string) {
    const summary = await this.emailSyncService.getOwned(firebaseUid, id);
    const user = await this.usersService.getByFirebaseUidOrThrow(firebaseUid);
    await this.connectionsService.getConnectionOrThrow(user.id);
    const refreshToken = await this.connectionsService.getDecryptedRefreshToken(user.id);
    try {
      const { texto, ehPreview } = await this.gmailApiClient.fetchFullBody(
        refreshToken as string,
        summary.gmailMessageId,
      );
      return { corpo: texto, ehPreview };
    } catch (error) {
      throw mapearErroGmail(error, 'Este e-mail não existe mais no Gmail — ele pode ter sido apagado por lá.');
    }
  }

  /** Arquivar: tira o e-mail da caixa de entrada no Gmail de verdade (`messages.modify`,
   *  removendo só o label `INBOX`) — totalmente reversível pelo próprio Gmail — e remove a linha
   *  local na MESMA requisição, já que o sync incremental nunca detectaria essa remoção sozinho.
   *
   *  Se a chamada ao Gmail falhar porque a mensagem já não existe mais lá (404 — por exemplo,
   *  apagada direto no Gmail), não há nada para arquivar, mas a linha local não pode ficar presa
   *  para sempre por isso: segue como se a ação tivesse funcionado e remove a linha mesmo assim.
   *  Qualquer outra falha (token revogado, Gmail indisponível) vira uma resposta HTTP honesta via
   *  `mapearErroGmail`, nunca um 500 cru nem um sucesso inventado. */
  @Post(':id/arquivar')
  async arquivar(@CurrentFirebaseUid() firebaseUid: string, @Param('id') id: string) {
    const summary = await this.emailSyncService.getOwned(firebaseUid, id);
    const user = await this.usersService.getByFirebaseUidOrThrow(firebaseUid);
    const connection = await this.connectionsService.getConnectionOrThrow(user.id);
    if (!connection.temEscopoModificacao) {
      throw new ForbiddenException('Reconecte o Gmail para arquivar ou excluir e-mails por aqui.');
    }
    const refreshToken = await this.connectionsService.getDecryptedRefreshToken(user.id);
    try {
      await this.gmailApiClient.arquivar(refreshToken as string, summary.gmailMessageId);
    } catch (error) {
      if (!gmailMensagemNaoEncontrada(error)) throw mapearErroGmail(error);
    }
    await this.emailSyncService.remover(summary.id);
    return { arquivado: true };
  }

  /** Excluir: manda o e-mail para a lixeira do Gmail (`messages.trash`, recuperável por ~30 dias
   *  — nunca `messages.delete`, que é permanente) e remove a linha local na mesma requisição.
   *  Mesmo tratamento de erro que `arquivar` acima: mensagem já ausente no Gmail (404) ainda
   *  remove a linha local; qualquer outra falha vira uma resposta HTTP honesta. */
  @Post(':id/excluir')
  async excluir(@CurrentFirebaseUid() firebaseUid: string, @Param('id') id: string) {
    const summary = await this.emailSyncService.getOwned(firebaseUid, id);
    const user = await this.usersService.getByFirebaseUidOrThrow(firebaseUid);
    const connection = await this.connectionsService.getConnectionOrThrow(user.id);
    if (!connection.temEscopoModificacao) {
      throw new ForbiddenException('Reconecte o Gmail para arquivar ou excluir e-mails por aqui.');
    }
    const refreshToken = await this.connectionsService.getDecryptedRefreshToken(user.id);
    try {
      await this.gmailApiClient.excluir(refreshToken as string, summary.gmailMessageId);
    } catch (error) {
      if (!gmailMensagemNaoEncontrada(error)) throw mapearErroGmail(error);
    }
    await this.emailSyncService.remover(summary.id);
    return { excluido: true };
  }
}
