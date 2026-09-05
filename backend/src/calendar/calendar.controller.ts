import {
  BadRequestException,
  Body,
  Controller,
  Delete,
  ForbiddenException,
  Get,
  Param,
  Post,
  Put,
  Query,
  UseGuards,
} from '@nestjs/common';
import { FirebaseAuthGuard } from '../auth/firebase-auth.guard';
import { CurrentFirebaseUid } from '../common/current-firebase-uid.decorator';
import { UsersService } from '../users/users.service';
import { GmailConnectionsService } from '../gmail/gmail-connections.service';
import { CalendarApiClient } from './calendar-api-client.service';
import { CriarEventoDto } from './dto/criar-evento.dto';
import { EventosMesQueryDto } from './dto/eventos-mes-query.dto';

const UM_DIA_MS = 24 * 60 * 60 * 1000;
const DIAS_EVENTOS_PROXIMOS = 7;
// Faixa razoável para `ano`: fora dela, `Date.UTC(ano, ...)` ainda produz um timestamp válido, mas
// `.toISOString()` em anos absurdos (ex.: 275760+) lança RangeError — um 500, não um 400. Validar
// aqui evita expor esse erro de runtime ao cliente.
const ANO_MINIMO = 2000;
const ANO_MAXIMO = 2100;

/** Agenda sempre-editável do usuário (CRUD completo sobre o Google Calendar), distinta do fluxo
 *  de confirmação de compromisso sugerido a partir de um e-mail em `email-reply.controller.ts`. */
@UseGuards(FirebaseAuthGuard)
@Controller('calendario')
export class CalendarController {
  constructor(
    private readonly usersService: UsersService,
    private readonly connectionsService: GmailConnectionsService,
    private readonly calendarApiClient: CalendarApiClient,
  ) {}

  @Get('eventos-proximos')
  async eventosProximos(@CurrentFirebaseUid() firebaseUid: string) {
    const refreshToken = await this.refreshTokenComEscopoAgenda(firebaseUid);
    const agora = new Date();
    const daquiASeteDias = new Date(
      agora.getTime() + DIAS_EVENTOS_PROXIMOS * UM_DIA_MS,
    );
    return this.calendarApiClient.listarEventos(
      refreshToken,
      agora.toISOString(),
      daquiASeteDias.toISOString(),
    );
  }

  @Get('eventos-mes')
  async eventosMes(
    @CurrentFirebaseUid() firebaseUid: string,
    @Query() query: EventosMesQueryDto,
  ) {
    const ano = Number(query.ano);
    const mes = Number(query.mes);
    if (mes < 1 || mes > 12) {
      throw new BadRequestException('mes deve estar entre 1 e 12.');
    }
    if (!Number.isInteger(ano) || ano < ANO_MINIMO || ano > ANO_MAXIMO) {
      throw new BadRequestException(
        `ano deve estar entre ${ANO_MINIMO} e ${ANO_MAXIMO}.`,
      );
    }

    const refreshToken = await this.refreshTokenComEscopoAgenda(firebaseUid);
    // Intervalo [primeiro dia do mês, primeiro dia do mês seguinte) em UTC — só delimita a janela
    // de busca no Google Calendar, não representa o horário local do usuário (o próprio evento
    // guarda seu offset original, preservado por `criarEventoCompleto`/`atualizarEvento`).
    const inicioMes = new Date(Date.UTC(ano, mes - 1, 1)).toISOString();
    const inicioMesSeguinte = new Date(Date.UTC(ano, mes, 1)).toISOString();
    return this.calendarApiClient.listarEventos(
      refreshToken,
      inicioMes,
      inicioMesSeguinte,
    );
  }

  @Post('criar-evento')
  async criarEvento(
    @CurrentFirebaseUid() firebaseUid: string,
    @Body() dto: CriarEventoDto,
  ) {
    this.validarIntervalo(dto);
    const refreshToken = await this.refreshTokenComEscopoAgenda(firebaseUid);
    return this.calendarApiClient.criarEventoCompleto(refreshToken, {
      titulo: dto.titulo,
      descricao: dto.descricao ?? '',
      dataHoraInicio: dto.dataHoraInicio,
      dataHoraFim: dto.dataHoraFim,
      ehDiaInteiro: dto.ehDiaInteiro ?? false,
    });
  }

  @Put('evento/:id')
  async atualizarEvento(
    @CurrentFirebaseUid() firebaseUid: string,
    @Param('id') id: string,
    @Body() dto: CriarEventoDto,
  ) {
    this.validarIntervalo(dto);
    const refreshToken = await this.refreshTokenComEscopoAgenda(firebaseUid);
    return this.calendarApiClient.atualizarEvento(refreshToken, id, {
      titulo: dto.titulo,
      descricao: dto.descricao ?? '',
      dataHoraInicio: dto.dataHoraInicio,
      dataHoraFim: dto.dataHoraFim,
      ehDiaInteiro: dto.ehDiaInteiro ?? false,
    });
  }

  /** `@IsISO8601()` no DTO só garante que cada data isoladamente é uma data válida — nada impede
   *  um término antes (ou igual a) do início, o que criaria um evento invertido ou de duração
   *  zero no Google Calendar. */
  private validarIntervalo(dto: CriarEventoDto): void {
    const inicio = new Date(dto.dataHoraInicio);
    const fim = new Date(dto.dataHoraFim);
    if (fim.getTime() <= inicio.getTime()) {
      throw new BadRequestException(
        'dataHoraFim deve ser depois de dataHoraInicio.',
      );
    }
  }

  @Delete('evento/:id')
  async deletarEvento(
    @CurrentFirebaseUid() firebaseUid: string,
    @Param('id') id: string,
  ) {
    const refreshToken = await this.refreshTokenComEscopoAgenda(firebaseUid);
    await this.calendarApiClient.deletarEvento(refreshToken, id);
    return { sucesso: true };
  }

  /** Repete o mesmo check em toda rota (usuário -> conexão Gmail -> escopo de agenda concedido),
   *  igual ao padrão em `email-reply.controller.ts`, só que fatorado aqui porque toda rota deste
   *  controller precisa dele. */
  private async refreshTokenComEscopoAgenda(
    firebaseUid: string,
  ): Promise<string> {
    const user = await this.usersService.getByFirebaseUidOrThrow(firebaseUid);
    const connection = await this.connectionsService.getConnectionOrThrow(
      user.id,
    );
    if (!connection.temEscopoAgenda) {
      throw new ForbiddenException('Reconecte o Gmail para usar a agenda.');
    }
    const refreshToken = await this.connectionsService.getDecryptedRefreshToken(
      user.id,
    );
    return refreshToken as string;
  }
}
