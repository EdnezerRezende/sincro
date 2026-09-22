import { Logger } from '@nestjs/common';
import { inspect } from 'node:util';
import { FinanceEmailProcessor } from './finance-email-processor.service';
import { EmailFinanceRegexParserService } from './email-finance-regex-parser.service';

function deps() {
  const prisma = {
    lancamentoFinanceiro: {
      findUnique: jest.fn().mockResolvedValue(null),
      create: jest.fn(),
      updateMany: jest.fn(),
      deleteMany: jest.fn(),
    },
  };
  const gmail = {
    fetchFullBodyComAnexos: jest
      .fn()
      .mockResolvedValue({ texto: '', ehPreview: false, anexos: [] }),
    fetchPdfAttachmentText: jest.fn().mockResolvedValue(null),
  };
  return {
    prisma,
    gmail,
    processor: new FinanceEmailProcessor(
      prisma as any,
      gmail as any,
      new EmailFinanceRegexParserService(),
    ),
  };
}
const nubank = {
  gmailMessageId: 'm1',
  remetente: 'Nubank <todomundo@nubank.com.br>',
  assunto: 'A fatura do seu cartão Nubank está fechada',
  recebidoEm: new Date('2026-09-08T04:37:16Z'),
};

describe('FinanceEmailProcessor.processar', () => {
  it('nao → remove lançamento da máquina, sem buscar corpo', async () => {
    const d = deps();
    const r = await d.processor.processar(
      'u1',
      'rt',
      { ...nubank, assunto: 'Extrato da sua conta do Nubank' },
      { marcado: false },
    );
    expect(r).toMatchObject({ transitorio: false, acao: 'removido' });
    expect(d.gmail.fetchFullBodyComAnexos).not.toHaveBeenCalled();
    expect(d.prisma.lancamentoFinanceiro.deleteMany).toHaveBeenCalledWith({
      where: {
        userId: 'u1',
        emailMessageId: 'm1',
        origem: 'EMAIL_PARSER',
        status: 'PENDENTE_REVISAO',
      },
    });
  });
  it('forte sem lançamento → create PENDENTE_REVISAO/EMAIL_PARSER', async () => {
    const d = deps();
    d.gmail.fetchFullBodyComAnexos.mockResolvedValue({
      texto: 'Sua fatura já está fechada, vence no dia 15 de setembro',
      ehPreview: false,
      anexos: [],
    });
    const r = await d.processor.processar('u1', 'rt', nubank, {
      marcado: false,
    });
    expect(r.acao).toBe('criado');
    expect(d.prisma.lancamentoFinanceiro.create).toHaveBeenCalledWith({
      data: expect.objectContaining({
        userId: 'u1',
        emailMessageId: 'm1',
        status: 'PENDENTE_REVISAO',
        origem: 'EMAIL_PARSER',
        tipo: 'FATURA_CARTAO',
        valor: null,
        dataVencimento: new Date(Date.UTC(2026, 8, 15)),
      }),
    });
  });
  it('lançamento pendente da máquina existente → updateMany condicionado', async () => {
    const d = deps();
    d.prisma.lancamentoFinanceiro.findUnique.mockResolvedValue({
      id: 'l1',
      origem: 'EMAIL_PARSER',
      status: 'PENDENTE_REVISAO',
    });
    d.gmail.fetchFullBodyComAnexos.mockResolvedValue({
      texto: 'Total da fatura R$ 520,61\nVencimento 17/09/2026',
      ehPreview: false,
      anexos: [],
    });
    const r = await d.processor.processar('u1', 'rt', nubank, {
      marcado: false,
    });
    expect(r.acao).toBe('atualizado');
    expect(d.prisma.lancamentoFinanceiro.updateMany).toHaveBeenCalledWith({
      where: {
        userId: 'u1',
        emailMessageId: 'm1',
        origem: 'EMAIL_PARSER',
        status: 'PENDENTE_REVISAO',
      },
      data: expect.objectContaining({ valor: 520.61 }),
    });
  });
  it('lançamento confirmado → não toca', async () => {
    const d = deps();
    d.prisma.lancamentoFinanceiro.findUnique.mockResolvedValue({
      id: 'l1',
      origem: 'EMAIL_PARSER',
      status: 'CONFIRMADO',
    });
    const r = await d.processor.processar('u1', 'rt', nubank, {
      marcado: false,
    });
    expect(r.acao).toBe('nada');
    expect(d.prisma.lancamentoFinanceiro.updateMany).not.toHaveBeenCalled();
    expect(d.prisma.lancamentoFinanceiro.create).not.toHaveBeenCalled();
  });
  it('parse null (fraco sem evidência) → remove', async () => {
    const d = deps();
    const r = await d.processor.processar(
      'u1',
      'rt',
      { ...nubank, assunto: 'Resumo das suas compras' },
      { marcado: false },
    );
    expect(r.acao).toBe('removido');
  });
  it('consulta o PDF só quando falta valor ou data, e complementa', async () => {
    const d = deps();
    const anexo = {
      filename: 'Nubank.pdf',
      mimeType: 'application/pdf',
      size: 10,
      attachmentId: 'a1',
    };
    d.gmail.fetchFullBodyComAnexos.mockResolvedValue({
      texto: 'Sua fatura já está fechada, vence no dia 15 de setembro',
      ehPreview: false,
      anexos: [anexo],
    });
    d.gmail.fetchPdfAttachmentText.mockResolvedValue(
      'Total da fatura R$ 1.234,56',
    );
    await d.processor.processar('u1', 'rt', nubank, { marcado: false });
    expect(d.gmail.fetchPdfAttachmentText).toHaveBeenCalledWith(
      'rt',
      'm1',
      anexo,
    );
    expect(d.prisma.lancamentoFinanceiro.create).toHaveBeenCalledWith({
      data: expect.objectContaining({ valor: 1234.56 }),
    });
  });
  it('não consulta o PDF quando o corpo já tem valor e data', async () => {
    const d = deps();
    d.gmail.fetchFullBodyComAnexos.mockResolvedValue({
      texto: 'Total da fatura R$ 10,00\nVencimento 10/10/2026',
      ehPreview: false,
      anexos: [
        {
          filename: 'x.pdf',
          mimeType: 'application/pdf',
          size: 1,
          attachmentId: 'a',
        },
      ],
    });
    await d.processor.processar('u1', 'rt', nubank, { marcado: false });
    expect(d.gmail.fetchPdfAttachmentText).not.toHaveBeenCalled();
  });
  it('erro 503 do Gmail → transitorio-mensagem, nada gravado', async () => {
    const d = deps();
    d.gmail.fetchFullBodyComAnexos.mockRejectedValue(
      Object.assign(new Error('x'), {
        response: { status: 503 },
        code: 503,
        config: {},
      }),
    );
    const r = await d.processor.processar('u1', 'rt', nubank, {
      marcado: false,
    });
    expect(r).toMatchObject({
      transitorio: true,
      classe: 'transitorio-mensagem',
      acao: 'erro',
    });
    expect(d.prisma.lancamentoFinanceiro.create).not.toHaveBeenCalled();
  });
  it('erro 404 → permanente, remove lançamento da máquina', async () => {
    const d = deps();
    d.gmail.fetchFullBodyComAnexos.mockRejectedValue(
      Object.assign(new Error('x'), {
        response: { status: 404 },
        code: 404,
        config: {},
      }),
    );
    const r = await d.processor.processar('u1', 'rt', nubank, {
      marcado: false,
    });
    expect(r).toMatchObject({
      transitorio: false,
      classe: 'permanente',
      acao: 'removido',
    });
    expect(d.prisma.lancamentoFinanceiro.deleteMany).toHaveBeenCalled();
  });
  it('exceção do parser → permanente, acao erro', async () => {
    const d = deps();
    d.gmail.fetchFullBodyComAnexos.mockRejectedValue(new TypeError('bug'));
    const r = await d.processor.processar('u1', 'rt', nubank, {
      marcado: false,
    });
    expect(r).toMatchObject({
      transitorio: false,
      classe: 'permanente',
      acao: 'erro',
    });
  });
  it('P2002 no create → tratado como corrida benigna', async () => {
    const d = deps();
    d.gmail.fetchFullBodyComAnexos.mockResolvedValue({
      texto: 'x',
      ehPreview: false,
      anexos: [],
    });
    d.prisma.lancamentoFinanceiro.create.mockRejectedValue({ code: 'P2002' });
    const r = await d.processor.processar('u1', 'rt', nubank, {
      marcado: false,
    });
    expect(r).toMatchObject({ transitorio: false, acao: 'nada' });
  });
  it('404 do Gmail + falha ao remover no Prisma → não lança, acao erro', async () => {
    const d = deps();
    d.gmail.fetchFullBodyComAnexos.mockRejectedValue(
      Object.assign(new Error('x'), {
        response: { status: 404 },
        code: 404,
        config: {},
      }),
    );
    d.prisma.lancamentoFinanceiro.deleteMany.mockRejectedValue({
      code: 'P2024',
    });
    const r = await d.processor.processar('u1', 'rt', nubank, {
      marcado: false,
    });
    expect(r).toMatchObject({
      transitorio: false,
      classe: 'permanente',
      acao: 'erro',
    });
  });
  it('lançamento existente não é da máquina (CONFIRMADO) + anexo PDF → nada, sem buscar PDF', async () => {
    const d = deps();
    const anexo = {
      filename: 'Nubank.pdf',
      mimeType: 'application/pdf',
      size: 10,
      attachmentId: 'a1',
    };
    d.prisma.lancamentoFinanceiro.findUnique.mockResolvedValue({
      id: 'l1',
      origem: 'EMAIL_PARSER',
      status: 'CONFIRMADO',
    });
    d.gmail.fetchFullBodyComAnexos.mockResolvedValue({
      texto: 'Sua fatura já está fechada, vence no dia 15 de setembro',
      ehPreview: false,
      anexos: [anexo],
    });
    const r = await d.processor.processar('u1', 'rt', nubank, {
      marcado: false,
    });
    expect(r.acao).toBe('nada');
    expect(d.gmail.fetchPdfAttachmentText).not.toHaveBeenCalled();
    expect(d.prisma.lancamentoFinanceiro.updateMany).not.toHaveBeenCalled();
    expect(d.prisma.lancamentoFinanceiro.create).not.toHaveBeenCalled();
  });
  it('lançamento pendente da máquina existente + anexo PDF → busca PDF e atualiza', async () => {
    const d = deps();
    const anexo = {
      filename: 'Nubank.pdf',
      mimeType: 'application/pdf',
      size: 10,
      attachmentId: 'a1',
    };
    d.prisma.lancamentoFinanceiro.findUnique.mockResolvedValue({
      id: 'l1',
      origem: 'EMAIL_PARSER',
      status: 'PENDENTE_REVISAO',
    });
    d.gmail.fetchFullBodyComAnexos.mockResolvedValue({
      texto: 'Sua fatura já está fechada, vence no dia 15 de setembro',
      ehPreview: false,
      anexos: [anexo],
    });
    d.gmail.fetchPdfAttachmentText.mockResolvedValue(
      'Total da fatura R$ 1.234,56',
    );
    const r = await d.processor.processar('u1', 'rt', nubank, {
      marcado: false,
    });
    expect(d.gmail.fetchPdfAttachmentText).toHaveBeenCalledWith(
      'rt',
      'm1',
      anexo,
    );
    expect(r.acao).toBe('atualizado');
    expect(d.prisma.lancamentoFinanceiro.updateMany).toHaveBeenCalledWith({
      where: {
        userId: 'u1',
        emailMessageId: 'm1',
        origem: 'EMAIL_PARSER',
        status: 'PENDENTE_REVISAO',
      },
      data: expect.objectContaining({ valor: 1234.56 }),
    });
  });
  it('lançamento existente ignorado pelo usuário → nada, sem escrita', async () => {
    const d = deps();
    d.prisma.lancamentoFinanceiro.findUnique.mockResolvedValue({
      id: 'l1',
      origem: 'EMAIL_PARSER',
      status: 'IGNORADO',
    });
    d.gmail.fetchFullBodyComAnexos.mockResolvedValue({
      texto: 'Sua fatura já está fechada, vence no dia 15 de setembro',
      ehPreview: false,
      anexos: [],
    });
    const r = await d.processor.processar('u1', 'rt', nubank, {
      marcado: false,
    });
    expect(r.acao).toBe('nada');
    expect(d.prisma.lancamentoFinanceiro.updateMany).not.toHaveBeenCalled();
    expect(d.prisma.lancamentoFinanceiro.create).not.toHaveBeenCalled();
  });
  it('lançamento existente criado manualmente (MANUAL/PENDENTE_REVISAO) → nada, sem escrita', async () => {
    const d = deps();
    d.prisma.lancamentoFinanceiro.findUnique.mockResolvedValue({
      id: 'l1',
      origem: 'MANUAL',
      status: 'PENDENTE_REVISAO',
    });
    d.gmail.fetchFullBodyComAnexos.mockResolvedValue({
      texto: 'Sua fatura já está fechada, vence no dia 15 de setembro',
      ehPreview: false,
      anexos: [],
    });
    const r = await d.processor.processar('u1', 'rt', nubank, {
      marcado: false,
    });
    expect(r.acao).toBe('nada');
    expect(d.prisma.lancamentoFinanceiro.updateMany).not.toHaveBeenCalled();
    expect(d.prisma.lancamentoFinanceiro.create).not.toHaveBeenCalled();
  });
  it('anexo PDF sem texto extraível → cria com valor null, usando a data do corpo', async () => {
    const d = deps();
    const anexo = {
      filename: 'Nubank.pdf',
      mimeType: 'application/pdf',
      size: 10,
      attachmentId: 'a1',
    };
    d.gmail.fetchFullBodyComAnexos.mockResolvedValue({
      texto: 'Sua fatura já está fechada, vence no dia 15 de setembro',
      ehPreview: false,
      anexos: [anexo],
    });
    d.gmail.fetchPdfAttachmentText.mockResolvedValue(null);
    const r = await d.processor.processar('u1', 'rt', nubank, {
      marcado: false,
    });
    expect(d.gmail.fetchPdfAttachmentText).toHaveBeenCalledWith(
      'rt',
      'm1',
      anexo,
    );
    expect(r.acao).toBe('criado');
    expect(d.prisma.lancamentoFinanceiro.create).toHaveBeenCalledWith({
      data: expect.objectContaining({
        valor: null,
        dataVencimento: new Date(Date.UTC(2026, 8, 15)),
      }),
    });
  });
});

describe('FinanceEmailProcessor — linha de auditoria (logDecisao)', () => {
  let logs: string[];
  let porNivel: Record<'log' | 'warn' | 'error', string[]>;
  let spies: jest.SpyInstance[];
  const fechada =
    'Sua fatura já está fechada, vence no dia 15 de setembro. Valor: R$ 99,90 CORPO-SECRETO';
  const ultima = () => logs[logs.length - 1];
  const linhasFinance = () => logs.filter((l) => l.startsWith('finance user='));
  /** Tudo depois do PRIMEIRO ` | assunto=` é UM JSON string: aspas, `|` e até um ` | assunto=`
   *  literal dentro do assunto não forjam campos nem quebram a recuperação. */
  const assuntoDaLinha = (linha: string): string => {
    const i = linha.indexOf(' | assunto=');
    expect(i).toBeGreaterThan(0);
    return JSON.parse(linha.slice(i + ' | assunto='.length)) as string;
  };
  class GaxiosError extends Error {
    constructor(
      message: string,
      public config: Record<string, unknown>,
      public response: { status: number },
    ) {
      super(message);
    }
  }
  const gaxios = (status: number) =>
    new GaxiosError(
      `Request failed with status code ${status}`,
      {
        url: 'https://gmail.googleapis.com/x',
        headers: { Authorization: 'Bearer ya29.TOKEN-SUPER-SECRETO' },
      },
      { status },
    );
  beforeEach(() => {
    logs = [];
    porNivel = { log: [], warn: [], error: [] };
    spies = (['log', 'warn', 'error'] as const).map((n) =>
      jest
        .spyOn(Logger.prototype, n)
        .mockImplementation((...args: unknown[]) => {
          // TODOS os argumentos, inspecionados a fundo: é assim que um objeto de erro passado ao
          // logger (com token dentro) apareceria no ConsoleLogger real.
          const linha = args.map((a) => inspect(a, { depth: 8 })).join(' ');
          logs.push(typeof args[0] === 'string' ? args[0] : linha);
          porNivel[n].push(linha);
        }),
    );
  });
  afterEach(() => spies.forEach((s) => s.mockRestore()));

  it('veto duro/brando/sem sinal: 1 linha com userId, rótulo do veto (sem regex) e desfecho alinhado ao retorno', async () => {
    const d = deps();
    d.prisma.lancamentoFinanceiro.deleteMany.mockResolvedValue({ count: 0 });
    const r = await d.processor.processar(
      'u1',
      'rt',
      { ...nubank, assunto: 'Extrato da sua conta do Nubank' },
      { marcado: false },
    );
    expect(logs).toHaveLength(1);
    expect(logs[0]).toContain(
      'finance user=u1 msg=m1 nivel=nao sinais=[] motivo="veto duro: extrato" → removido: descartado na triagem (nada a apagar)',
    );
    expect(logs[0]).not.toContain('(?<!');
    expect(logs[0]).not.toContain('\\b');
    expect(r.acao).toBe('removido');
    await d.processor.processar(
      'u1',
      'rt',
      { ...nubank, assunto: 'Saiba tudo sobre sua fatura' },
      { marcado: false },
    );
    expect(ultima()).toContain('motivo="veto brando: saiba"');
    await d.processor.processar(
      'u1',
      'rt',
      {
        ...nubank,
        assunto: 'O cadastro do seu Débito automático foi concluído.',
      },
      { marcado: false },
    );
    expect(ultima()).toContain(
      'motivo="veto duro: debito-automatico-confirmado"',
    );
    await d.processor.processar(
      'u1',
      'rt',
      {
        ...nubank,
        remetente: 'Ana <ana@gmail.com>',
        assunto: 'Almoço domingo?',
      },
      { marcado: false },
    );
    expect(ultima()).toContain(
      'motivo="sem sinal" → removido: descartado na triagem',
    );
  });
  it('descarte na triagem: "lançamento pendente apagado" só quando apagou de verdade; erro do Prisma vira erro com classe', async () => {
    const d = deps();
    const assunto = 'Extrato da sua conta do Nubank';
    d.prisma.lancamentoFinanceiro.deleteMany.mockResolvedValue({ count: 1 });
    await d.processor.processar(
      'u1',
      'rt',
      { ...nubank, assunto },
      { marcado: false },
    );
    expect(ultima()).toContain(
      '→ removido: descartado na triagem, lançamento pendente apagado',
    );
    d.prisma.lancamentoFinanceiro.deleteMany.mockResolvedValue({ count: 0 });
    await d.processor.processar(
      'u1',
      'rt',
      { ...nubank, assunto },
      { marcado: false },
    );
    expect(ultima()).toContain(
      '→ removido: descartado na triagem (nada a apagar)',
    );
    d.prisma.lancamentoFinanceiro.deleteMany.mockRejectedValue({
      code: 'P1001',
    });
    const r = await d.processor.processar(
      'u1',
      'rt',
      { ...nubank, assunto },
      { marcado: false },
    );
    expect(r.acao).toBe('erro');
    expect(ultima()).toContain('nivel=nao');
    expect(ultima()).toContain(
      '→ erro: permanente [object P1001] (permanente — versão carimbada, não volta)',
    );
    expect(porNivel.error.some((l) => l.includes('→ erro: permanente'))).toBe(
      true,
    );
  });
  it('parser recusa: a linha diz a causa (evidência negativa × sinal fraco) e quais evidências achou', async () => {
    const d = deps();
    d.prisma.lancamentoFinanceiro.deleteMany.mockResolvedValue({ count: 0 });
    d.gmail.fetchFullBodyComAnexos.mockResolvedValue({
      texto: 'Pagamento realizado com sucesso. Sua fatura foi paga.',
      ehPreview: false,
      anexos: [],
    });
    await d.processor.processar('u1', 'rt', nubank, { marcado: false });
    expect(ultima()).toContain(
      'nivel=forte sinais=[S1a] → removido: descartado no parser: evidência negativa no corpo',
    );
    d.gmail.fetchFullBodyComAnexos.mockResolvedValue({
      texto: 'Confira as novidades do mês no app.',
      ehPreview: false,
      anexos: [],
    });
    await d.processor.processar(
      'u1',
      'rt',
      {
        ...nubank,
        remetente: 'Coop Beta <contato@coopbeta.coop.br>',
        assunto: 'Informativo do seu consórcio',
      },
      { marcado: false },
    );
    expect(ultima()).toContain(
      'nivel=fraco sinais=[S6] → removido: descartado no parser: sinal fraco sem evidência suficiente (encontradas: nenhuma) (nada a apagar)',
    );
  });
  it('sucesso: a linha sai DEPOIS de gravar e diz o desfecho real (criado / duplicado / atualizado / corrida / count desconhecido)', async () => {
    const d = deps();
    d.gmail.fetchFullBodyComAnexos.mockResolvedValue({
      texto: fechada,
      ehPreview: false,
      anexos: [],
    });
    await d.processor.processar('u1', 'rt-TOKEN-SECRETO', nubank, {
      marcado: false,
    });
    expect(logs).toHaveLength(1);
    expect(logs[0]).toContain(
      'nivel=forte sinais=[S1a] → criado: FATURA_CARTAO valor=99.9 data=ok',
    );
    expect(logs[0]).not.toContain('CORPO-SECRETO');
    expect(logs[0]).not.toContain('TOKEN-SECRETO');

    d.prisma.lancamentoFinanceiro.create.mockRejectedValue({ code: 'P2002' });
    expect(
      (await d.processor.processar('u1', 'rt', nubank, { marcado: false }))
        .acao,
    ).toBe('nada');
    expect(ultima()).toContain('→ nada: duplicado (corrida P2002)');

    d.prisma.lancamentoFinanceiro.findUnique.mockResolvedValue({
      origem: 'EMAIL_PARSER',
      status: 'PENDENTE_REVISAO',
    });
    d.prisma.lancamentoFinanceiro.updateMany.mockResolvedValue({ count: 1 });
    expect(
      (await d.processor.processar('u1', 'rt', nubank, { marcado: false }))
        .acao,
    ).toBe('atualizado');
    expect(ultima()).toContain(
      '→ atualizado: FATURA_CARTAO valor=99.9 data=ok | assunto=',
    );

    d.prisma.lancamentoFinanceiro.updateMany.mockResolvedValue({ count: 0 });
    expect(
      (await d.processor.processar('u1', 'rt', nubank, { marcado: false }))
        .acao,
    ).toBe('nada');
    expect(ultima()).toContain(
      '→ nada: lançamento revisado pelo usuário durante o processamento (updateMany=0)',
    );

    d.prisma.lancamentoFinanceiro.updateMany.mockResolvedValue(undefined);
    expect(
      (await d.processor.processar('u1', 'rt', nubank, { marcado: false }))
        .acao,
    ).toBe('atualizado');
    expect(ultima()).toContain(
      '→ atualizado: FATURA_CARTAO valor=99.9 data=ok (count desconhecido)',
    );
  });
  it('lançamento já revisado/manual não é reavaliado — e o log diz isso, não silencia; S4 aparece nos sinais', async () => {
    const d = deps();
    d.gmail.fetchFullBodyComAnexos.mockResolvedValue({
      texto: fechada,
      ehPreview: false,
      anexos: [],
    });
    d.prisma.lancamentoFinanceiro.findUnique.mockResolvedValue({
      origem: 'EMAIL_PARSER',
      status: 'IGNORADO',
    });
    expect(
      (await d.processor.processar('u1', 'rt', nubank, { marcado: false }))
        .acao,
    ).toBe('nada');
    expect(ultima()).toContain(
      '→ nada: lançamento já ignorado (não reavaliado)',
    );
    d.prisma.lancamentoFinanceiro.findUnique.mockResolvedValue({
      origem: 'MANUAL',
      status: 'CONFIRMADO',
    });
    await d.processor.processar('u1', 'rt', nubank, { marcado: false });
    expect(ultima()).toContain('→ nada: lançamento já manual (não reavaliado)');
    d.prisma.lancamentoFinanceiro.findUnique.mockResolvedValue(null);
    await d.processor.processar(
      'u1',
      'rt',
      { ...nubank, assunto: 'Almoço domingo?' },
      { marcado: true },
    );
    expect(ultima()).toContain(
      'nivel=forte sinais=[S4] → criado: DESPESA valor=99.9 data=ok',
    );
  });
  it('erros do Gmail deixam linha no nível da severidade, com classe/código/HTTP, sem NUNCA imprimir o objeto (token)', async () => {
    const d = deps();
    d.gmail.fetchFullBodyComAnexos.mockRejectedValue(gaxios(404));
    d.prisma.lancamentoFinanceiro.deleteMany.mockResolvedValue({ count: 1 });
    expect(
      (await d.processor.processar('u1', 'rt', nubank, { marcado: false }))
        .acao,
    ).toBe('removido');
    expect(linhasFinance()).toHaveLength(1);
    expect(linhasFinance()[0]).toContain(
      'nivel=forte sinais=[S1a] → removido: mensagem não existe mais no Gmail (404), lançamento pendente apagado',
    );

    logs.length = 0;
    d.prisma.lancamentoFinanceiro.deleteMany.mockResolvedValue({ count: 0 });
    await d.processor.processar('u1', 'rt', nubank, { marcado: false });
    expect(ultima()).toContain(
      '→ removido: mensagem não existe mais no Gmail (404) (nada a apagar)',
    );

    logs.length = 0;
    d.gmail.fetchFullBodyComAnexos.mockRejectedValue(gaxios(503));
    const r503 = await d.processor.processar('u1', 'rt', nubank, {
      marcado: false,
    });
    expect(r503).toMatchObject({ transitorio: true, acao: 'erro' });
    expect(ultima()).toContain(
      'finance user=u1 msg=m1 nivel=forte sinais=[S1a] → erro: transitorio-mensagem [GaxiosError HTTP 503] (será reprocessado)',
    );
    expect(
      porNivel.warn.some((l) => l.includes('→ erro: transitorio-mensagem')),
    ).toBe(true);
    expect(porNivel.log.some((l) => l.includes('→ erro:'))).toBe(false);

    logs.length = 0;
    d.gmail.fetchFullBodyComAnexos.mockRejectedValue(gaxios(404));
    d.prisma.lancamentoFinanceiro.deleteMany.mockRejectedValue({
      code: 'P1001',
    });
    expect(
      (await d.processor.processar('u1', 'rt', nubank, { marcado: false }))
        .acao,
    ).toBe('erro');
    expect(ultima()).toContain(
      '→ erro: mensagem não existe mais no Gmail (404), mas falhou ao apagar o lançamento pendente [object P1001]',
    );
    expect(
      porNivel.error.some((l) => l.includes('→ erro: mensagem não existe')),
    ).toBe(true);

    // Nenhum argumento de nenhum nível, inspecionado a fundo, carrega o bearer token.
    const tudo = [...porNivel.log, ...porNivel.warn, ...porNivel.error].join(
      '\n',
    );
    expect(tudo).not.toContain('ya29');
    expect(tudo).not.toContain('Authorization');
    expect(tudo).toContain(
      'finance user=u1 msg=m1 falha no processamento (transitorio-mensagem) [GaxiosError HTTP 503] | mensagem="Request failed with status code 503"',
    );
  });
  it('assunto hostil: controles Unicode viram espaço; aspas, | e " | assunto=" literal não forjam campos; corte por code point; vazio sinalizado', async () => {
    const d = deps();
    const forjado =
      'Extrato\n[Nest] LOG\u0085finance user=vitima msg=FORJADO\u001e→ criado\u001b[31m x\u0000y z​w\r\nfim';
    await d.processor.processar(
      'u1',
      'rt',
      { ...nubank, assunto: forjado },
      { marcado: false },
    );
    expect(logs).toHaveLength(1);
    expect(logs[0]).not.toMatch(/[\p{Cc}\p{Cf}\p{Zl}\p{Zp}]/u);
    expect(assuntoDaLinha(logs[0])).toBe(
      'Extrato [Nest] LOG finance user=vitima msg=FORJADO → criado [31m x y z w fim',
    );
    expect(logs[0].startsWith('finance user=u1 msg=m1 ')).toBe(true);
    expect(logs[0].split('\n')).toHaveLength(1);

    logs.length = 0;
    const forjaCampos =
      'Extrato "premium" | msg=FORJADO" motivo="veto duro: nada" → criado: FATURA_CARTAO valor=0 data=ok | assunto="ok';
    await d.processor.processar(
      'u1',
      'rt',
      { ...nubank, assunto: forjaCampos },
      { marcado: false },
    );
    // 105 code points: cortado em 80 por desenho, mas o campo continua um JSON íntegro
    expect(assuntoDaLinha(logs[0])).toBe(
      `${Array.from(forjaCampos).slice(0, 79).join('')}…`,
    );
    // o assunto vai como JSON: aspas escapadas, e só o PRIMEIRO " | assunto=" é o campo real
    expect(logs[0]).toContain(
      ' | assunto="Extrato \\"premium\\" | msg=FORJADO\\" motivo=',
    );
    expect(logs[0].startsWith('finance user=u1 msg=m1 ')).toBe(true);

    logs.length = 0;
    const longo = `Extrato da sua conta ${'a'.repeat(52)}😀resto${'b'.repeat(40)}`;
    await d.processor.processar(
      'u1',
      'rt',
      { ...nubank, assunto: longo },
      { marcado: false },
    );
    const trecho = assuntoDaLinha(logs[0]);
    expect(Array.from(trecho)).toHaveLength(80);
    expect(trecho.endsWith('…')).toBe(true);
    expect(Buffer.from(trecho, 'utf8').toString('utf8')).toBe(trecho); // sem surrogate solitário

    logs.length = 0;
    await d.processor.processar(
      'u1',
      'rt',
      { ...nubank, assunto: ' \t ' },
      { marcado: false },
    );
    expect(assuntoDaLinha(logs[0])).toBe('(sem assunto)');
  });
  it('deleteMany sem count: não afirma "nada a apagar", registra a dúvida', async () => {
    const d = deps();
    d.prisma.lancamentoFinanceiro.deleteMany.mockResolvedValue({});
    await d.processor.processar(
      'u1',
      'rt',
      { ...nubank, assunto: 'Extrato da sua conta do Nubank' },
      { marcado: false },
    );
    expect(ultima()).toContain(
      '→ removido: descartado na triagem (apagados desconhecido)',
    );
  });
  it('401 → transitorio-conta em warn; erro em fetchPdfAttachmentText também deixa linha; code igual ao status não duplica', async () => {
    const d = deps();
    d.gmail.fetchFullBodyComAnexos.mockRejectedValue(gaxios(401));
    const r401 = await d.processor.processar('u1', 'rt', nubank, {
      marcado: false,
    });
    expect(r401).toMatchObject({
      transitorio: true,
      classe: 'transitorio-conta',
      acao: 'erro',
    });
    expect(
      porNivel.warn.some((l) =>
        l.includes(
          '→ erro: transitorio-conta [GaxiosError HTTP 401] (será reprocessado)',
        ),
      ),
    ).toBe(true);

    logs.length = 0;
    d.gmail.fetchFullBodyComAnexos.mockResolvedValue({
      texto: 'Sua fatura já está fechada, confira o PDF anexo',
      ehPreview: false,
      anexos: [
        {
          filename: 'fatura.pdf',
          mimeType: 'application/pdf',
          size: 10,
          attachmentId: 'a',
        },
      ],
    });
    d.gmail.fetchPdfAttachmentText.mockRejectedValue({
      config: { url: 'x' },
      code: 503,
      response: { status: 503 },
    });
    const rPdf = await d.processor.processar('u1', 'rt', nubank, {
      marcado: false,
    });
    expect(rPdf.acao).toBe('erro');
    expect(ultima()).toContain(
      '→ erro: transitorio-mensagem [object HTTP 503] (será reprocessado)',
    );
    expect(ultima()).not.toContain('503 HTTP 503');
  });
  it('mensagem do erro: cortada por code point com marca (sem surrogate solitário) e serializada como JSON, sem forjar prefixo', async () => {
    const d = deps();
    const msg = `${'x'.repeat(159)}😀 finance user=vitima msg=FORJADO → criado\n${'y'.repeat(400)}`;
    d.gmail.fetchFullBodyComAnexos.mockRejectedValue(
      new GaxiosError(msg, { url: 'x' }, { status: 503 }),
    );
    await d.processor.processar('u1', 'rt', nubank, { marcado: false });
    // `logs` guarda o 1º argumento cru (sem as aspas do inspect), que é a linha em si
    const diag = logs.find((l) => l.includes('falha no processamento'));
    expect(
      porNivel.warn.some((l) => l.includes('falha no processamento')),
    ).toBe(true);
    expect(diag).toBeDefined();
    expect(
      diag!.startsWith(
        'finance user=u1 msg=m1 falha no processamento (transitorio-mensagem) [GaxiosError HTTP 503] | mensagem=',
      ),
    ).toBe(true);
    const mensagem = JSON.parse(
      diag!.slice(diag!.indexOf('| mensagem=') + '| mensagem='.length),
    ) as string;
    expect(Array.from(mensagem)).toHaveLength(160);
    expect(mensagem.endsWith('…')).toBe(true);
    expect(Buffer.from(diag!, 'utf8').toString('utf8')).toBe(diag!);
    expect(diag!.split('\n')).toHaveLength(1);
    expect(diag!.split('finance user=')[0]).toBe('');
  });
  it('a linha inteira nunca passa de 300 chars — nem com assunto legítimo longo + erro, nem com 80 aspas/barras que dobram no JSON', async () => {
    const d = deps();
    const userId = 'clx9a7b2k0000qwer1234asdf';
    const msg = { ...nubank, gmailMessageId: '18f0a1b2c3d4e5f6' };
    d.prisma.lancamentoFinanceiro.deleteMany.mockRejectedValue({
      code: 'P1001',
    });
    await d.processor.processar(
      userId,
      'rt',
      {
        ...msg,
        assunto:
          'O cadastro do seu Débito automático foi concluído com sucesso para a sua fatura do cartão Ultravioleta Black',
      },
      { marcado: false },
    );
    expect(ultima().length).toBeLessThanOrEqual(300);
    expect(assuntoDaLinha(ultima()).endsWith('…')).toBe(true);

    for (const ch of ['"', '\\']) {
      logs.length = 0;
      await d.processor.processar(
        userId,
        'rt',
        { ...msg, assunto: `Extrato da conta ${ch.repeat(80)}` },
        { marcado: false },
      );
      expect(ultima().length).toBeLessThanOrEqual(300);
      expect(() => assuntoDaLinha(ultima())).not.toThrow();
    }

    logs.length = 0;
    d.prisma.lancamentoFinanceiro.deleteMany.mockResolvedValue({ count: 0 });
    await d.processor.processar(
      userId,
      'rt',
      { ...msg, assunto: 'Extrato da sua conta' },
      { marcado: false },
    );
    expect(assuntoDaLinha(ultima())).toBe('Extrato da sua conta'); // curto: nada cortado
  });
});
