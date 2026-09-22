import {
  evidenciasDeCobranca,
  evidenciaSuficiente,
  temEvidenciaNegativa,
} from './finance-evidence';

const r = new Date('2026-09-01T00:00:00Z');
const ev = (texto: string, anexos: { filename: string }[] = []) =>
  evidenciasDeCobranca(
    texto,
    anexos.map((a) => ({
      ...a,
      mimeType: 'application/pdf',
      size: 1,
      attachmentId: 'x',
    })),
    r,
  );

describe('evidenciasDeCobranca', () => {
  it('E1 only with a cobrança anchor and value > 0', () => {
    expect(ev('Valor a pagar: R$ 129,90')).toEqual(new Set(['E1']));
    expect(ev('Você recebeu um Pix no valor de R$ 500,00')).toEqual(new Set());
    expect(ev('Valor: R$ 500,00')).toEqual(new Set());
    expect(ev('Total da fatura atual: R$ 0,00')).toEqual(new Set());
  });
  it('E2 with DATE_ANCHORS, including day-only', () => {
    expect(ev('A mensalidade vence dia 10 — valor R$ 1.200,00')).toEqual(
      new Set(['E2']),
    );
    expect(ev('Vencimento da apólice 15/10/2026')).toEqual(new Set(['E2']));
    expect(ev('vencimento em breve')).toEqual(new Set());
  });
  it('E3 barcode, E4 pix + currency same/next line, E5 attached phrase, E6 attachment name', () => {
    expect(
      ev('34191.79001 01043.510047 91020.150008 1 84410000012345'),
    ).toEqual(new Set(['E3']));
    expect(ev('Pix copia e cola\nR$ 89,90')).toEqual(new Set(['E4']));
    expect(ev('Pix copia e cola\n\n\nR$ 89,90')).toEqual(new Set());
    expect(ev('Sua fatura da Starlink está anexada')).toEqual(new Set(['E5']));
    expect(ev('Olá', [{ filename: 'Fatura_082026.PDF' }])).toEqual(
      new Set(['E6']),
    );
    expect(ev('Olá', [{ filename: 'Cobrança_09-2026.pdf' }])).toEqual(
      new Set(['E6']),
    );
  });
  it('E7 attachment is a CSV/XLS(X) sheet, regardless of its name; never XML', () => {
    expect(ev('Olá', [{ filename: 'nubank-2026-09-15.csv' }])).toEqual(
      new Set(['E7']),
    );
    expect(ev('Olá', [{ filename: 'lancamentos.XLSX' }])).toEqual(
      new Set(['E7']),
    );
    expect(ev('Olá', [{ filename: 'relatorio.csv ' }])).toEqual(
      new Set(['E7']),
    );
    // planilha nunca é E6 (só E7): o nome não pode furar a trava de documento/tema
    expect(ev('Olá', [{ filename: 'Fatura.csv' }])).toEqual(new Set(['E7']));
    expect(ev('Olá', [{ filename: 'fatura-2025.xlsx' }])).toEqual(
      new Set(['E7']),
    );
    expect(ev('Olá', [{ filename: 'Fatura_082026.pdf' }])).toEqual(
      new Set(['E6']),
    );
    expect(ev('Olá', [{ filename: 'foto.csv.png' }])).toEqual(new Set());
    expect(ev('Olá', [{ filename: 'nfe-123.xml' }])).toEqual(new Set());
    expect(ev('Olá', [{ filename: 'convite.xml' }])).toEqual(new Set());
  });
  it('ignores text past CABECA_EVIDENCIA', () => {
    expect(ev(`${'x'.repeat(1500)} Valor a pagar: R$ 10,00`)).toEqual(
      new Set(),
    );
  });
});

describe('evidenciaSuficiente', () => {
  it('E1/E3/E4/E5/E6 alone suffice; E2 needs a cobrança noun and E7 a cobrança document in the subject', () => {
    expect(evidenciaSuficiente(new Set(['E1']), false)).toBe(true);
    expect(evidenciaSuficiente(new Set(['E6']), false)).toBe(true);
    // planilha anexa só conta quando o assunto nomeia o DOCUMENTO de cobrança: "Relatório anual
    // do seu consórcio" + cotas.xlsx tem substantivo genérico (consórcio) mas não documento
    expect(evidenciaSuficiente(new Set(['E7']), false)).toBe(false);
    expect(evidenciaSuficiente(new Set(['E7']), true)).toBe(false);
    expect(evidenciaSuficiente(new Set(['E7']), true, true)).toBe(true);
    // tema fiscal: nome de anexo (E6 pdf / E7) e data nunca bastam; só cobrança explícita no corpo
    expect(evidenciaSuficiente(new Set(['E6']), true, false, true)).toBe(false);
    expect(evidenciaSuficiente(new Set(['E2', 'E7']), true, false, true)).toBe(
      false,
    );
    expect(evidenciaSuficiente(new Set(['E1']), true, false, true)).toBe(true);
    expect(evidenciaSuficiente(new Set(['E2']), true)).toBe(true);
    expect(evidenciaSuficiente(new Set(['E2']), false)).toBe(false);
    expect(evidenciaSuficiente(new Set(), true)).toBe(false);
  });
});

describe('temEvidenciaNegativa', () => {
  it.each([
    'Fatura anterior paga. Fatura de outubro disponível',
    'Fatura anterior paga: a atual vence dia 10',
    'Pagamento confirmado. Sua próxima fatura chegou',
    'Sua fatura foi paga; fatura de novembro disponível',
    'Fatura quitada. Boleto de outubro emitido',
    'Fatura, já paga, e a próxima em aberto',
  ])(
    'liquidação numa oração não é negativa se outra traz cobrança vigente: %s',
    (assunto) => {
      expect(temEvidenciaNegativa('Valor a pagar: R$ 120,00', assunto)).toBe(
        false,
      );
    },
  );
  it('a mesma regra por oração vale numa LINHA do corpo', () => {
    expect(
      temEvidenciaNegativa(
        'Recebemos o pagamento da sua fatura anterior. A fatura de outubro já está disponível.\nValor a pagar: R$ 120,00',
        'A fatura do seu cartão Nubank está fechada',
      ),
    ).toBe(false);
    expect(
      temEvidenciaNegativa(
        'Recebemos o pagamento da sua fatura. Obrigado!',
        'Sua fatura',
      ),
    ).toBe(true);
  });
  it('liquidação sem cobrança vigente continua negativa', () => {
    expect(
      temEvidenciaNegativa('Obrigado!', 'Sua fatura foi paga. Obrigado'),
    ).toBe(true);
  });
  it.each([
    ['Recebemos seu pagamento. Obrigado!', ''],
    ['Pesquisa de satisfação: avalie seu atendimento', ''],
    ['Você recebeu um Pix de Fulano no valor de R$ 500,00', ''],
    ['Sua compra no valor de R$ 89,90 foi aprovada', ''],
    ['Depósito recebido', ''],
    ['Estorno realizado', ''],
    ['Olá\n\nO pagamento de boleto foi agendado', ''],
    ['Olá', 'Você recebeu um Pix de Fulano'],
  ])('"%s" / assunto "%s" → true', (texto, assunto) => {
    expect(temEvidenciaNegativa(texto, assunto)).toBe(true);
  });
  it('only looks at the first 3 non-empty lines', () => {
    expect(temEvidenciaNegativa('a\nb\nc\nRecebemos seu pagamento', '')).toBe(
      false,
    );
  });
  it('a pending invoice is not negative', () => {
    expect(
      temEvidenciaNegativa(
        'Sua fatura já está fechada, vence no dia 15 de setembro',
        'A fatura do seu cartão está fechada',
      ),
    ).toBe(false);
  });
  it('checks isSettledPaymentSubject on the subject too, not just the first 3 body lines', () => {
    expect(
      temEvidenciaNegativa(
        'Valor a pagar: R$ 200,00',
        'Pagamento da fatura confirmado',
      ),
    ).toBe(true);
    expect(
      temEvidenciaNegativa('Valor a pagar: R$ 200,00', 'Fatura quitada'),
    ).toBe(true);
    expect(
      temEvidenciaNegativa(
        'Valor a pagar: R$ 200,00',
        'A fatura do seu cartão está fechada',
      ),
    ).toBe(false);
  });
});
