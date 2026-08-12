import { Injectable } from '@nestjs/common';
import Anthropic from '@anthropic-ai/sdk';

export interface CompromissoSugerido {
  tituloCompromisso: string;
  dataHoraLimite: string; // ISO
  antecedenciaMinutos: number;
}

@Injectable()
export class EmailCommitmentExtractionService {
  constructor(private readonly client: Anthropic) {}

  /** Never throws — a failure here (API error or a malformed response) must never undo an
   *  already-successful send, so every failure mode degrades to "no commitment found". */
  async extrair(texto: string): Promise<CompromissoSugerido | null> {
    try {
      const response = await this.client.messages.create({
        model: 'claude-haiku-4-5-20251001',
        max_tokens: 300,
        messages: [
          {
            role: 'user',
            content:
              'Analise o texto abaixo, escrito como resposta a um e-mail. Identifique se há uma ' +
              'promessa explícita de entrega, reunião ou ação futura com data/horário definido. ' +
              'Se houver, responda apenas com um JSON no formato {"tituloCompromisso": "...", ' +
              '"dataHoraLimite": "AAAA-MM-DDTHH:mm:ss" (data/hora completa, assumindo o ano atual ' +
              'se omitido), "antecedenciaMinutos": 60 ou 1440 (60 para tarefas simples, 1440 para ' +
              'tarefas complexas)}. Se não houver nenhuma promessa com data/horário claro, responda ' +
              'apenas com a palavra null, sem mais nada.\n\n' +
              `Texto: ${texto}`,
          },
        ],
      });
      const block = response.content[0];
      const text = (block.type === 'text' ? block.text : '').trim();
      if (text === 'null') return null;
      const parsed = JSON.parse(text) as Partial<CompromissoSugerido>;
      if (!parsed.tituloCompromisso || !parsed.dataHoraLimite || !parsed.antecedenciaMinutos) return null;
      return {
        tituloCompromisso: parsed.tituloCompromisso,
        dataHoraLimite: parsed.dataHoraLimite,
        antecedenciaMinutos: parsed.antecedenciaMinutos === 60 ? 60 : 1440,
      };
    } catch {
      return null;
    }
  }
}
