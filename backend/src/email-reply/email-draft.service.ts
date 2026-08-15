import { Injectable } from '@nestjs/common';
import Anthropic from '@anthropic-ai/sdk';

export interface RascunhosGerados {
  direto: string;
  formal: string;
  padrao: string;
}

@Injectable()
export class EmailDraftService {
  constructor(private readonly client: Anthropic) {}

  /** Unlike LlmEmailClassifier (which runs unattended in a background cron job and must never
   *  throw), this runs synchronously while a person is looking at the screen, able to retry — so
   *  a failure here is allowed to propagate; the controller/mobile layer shows a calm retry UI
   *  instead of silently returning empty drafts. */
  async gerar(params: { remetente: string; assunto: string; corpo: string }): Promise<RascunhosGerados> {
    const response = await this.client.messages.create({
      model: 'claude-haiku-4-5-20251001',
      max_tokens: 600,
      messages: [
        {
          role: 'user',
          content:
            'Escreva 3 rascunhos de resposta para o e-mail abaixo, em português, um para cada tom: ' +
            '"direto" (curto e objetivo), "formal" (educado e completo), "padrao" (equilibrado). ' +
            'Responda apenas com um JSON no formato {"direto": "...", "formal": "...", "padrao": "..."}, ' +
            'sem texto extra.\n\n' +
            `De: ${params.remetente}\nAssunto: ${params.assunto}\nCorpo: ${params.corpo}`,
        },
      ],
    });
    const block = response.content[0];
    const text = block.type === 'text' ? block.text : '';
    const parsed = JSON.parse(text) as Partial<RascunhosGerados>;
    if (!parsed.direto || !parsed.formal || !parsed.padrao) {
      throw new Error('Resposta da IA não trouxe os 3 rascunhos esperados.');
    }
    return { direto: parsed.direto, formal: parsed.formal, padrao: parsed.padrao };
  }
}
