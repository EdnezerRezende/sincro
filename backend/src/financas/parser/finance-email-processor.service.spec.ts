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
