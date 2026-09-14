import { validate } from 'class-validator';
import { plainToInstance } from 'class-transformer';
import { CriarEventoDto } from './criar-evento.dto';

const base = {
  titulo: 'Reunião',
  dataHoraInicio: '2026-09-01T15:00:00-03:00',
  dataHoraFim: '2026-09-01T16:00:00-03:00',
};

describe('CriarEventoDto — categoria', () => {
  it('aceita SOCIAL, TRABALHO e GERAL', async () => {
    for (const categoria of ['SOCIAL', 'TRABALHO', 'GERAL']) {
      const dto = plainToInstance(CriarEventoDto, { ...base, categoria });
      const erros = await validate(dto);
      expect(erros).toHaveLength(0);
    }
  });

  it('aceita ausência de categoria', async () => {
    const dto = plainToInstance(CriarEventoDto, base);
    const erros = await validate(dto);
    expect(erros).toHaveLength(0);
  });

  it('rejeita FINANCEIRO — reservado ao fluxo de sincronização de Finanças', async () => {
    const dto = plainToInstance(CriarEventoDto, { ...base, categoria: 'FINANCEIRO' });
    const erros = await validate(dto);
    expect(erros).not.toHaveLength(0);
    expect(erros[0].property).toBe('categoria');
  });

  it('rejeita um valor arbitrário', async () => {
    const dto = plainToInstance(CriarEventoDto, { ...base, categoria: 'QUALQUER_COISA' });
    const erros = await validate(dto);
    expect(erros).not.toHaveLength(0);
  });
});
