import { Injectable, Logger } from '@nestjs/common';
import Anthropic from '@anthropic-ai/sdk';
import {
  EmailClassification,
  EmailClassificationContext,
  EmailClassifier,
  EmailToClassify,
} from './email-classifier.interface';

export const ANTHROPIC_CLIENT = 'ANTHROPIC_CLIENT';

@Injectable()
export class LlmEmailClassifier implements EmailClassifier {
  private readonly logger = new Logger(LlmEmailClassifier.name);

  constructor(private readonly client: Anthropic) {}

  async classify(email: EmailToClassify, context: EmailClassificationContext): Promise<EmailClassification> {
    const tom = context.tomPreferido === 'LEVEMENTE_EXPLICATIVO' ? 'levemente mais explicativo' : 'direto e curto';
    try {
      const response = await this.client.messages.create({
        model: 'claude-haiku-4-5-20251001',
        max_tokens: 200,
        messages: [
          {
            role: 'user',
            content:
              `Classifique este e-mail como PRECISA_ATENCAO ou PODE_ESPERAR, e escreva um resumo de ` +
              `1 frase curta no tom ${tom}. Responda apenas com um JSON no formato ` +
              `{"categoria": "PRECISA_ATENCAO" | "PODE_ESPERAR", "resumoCurto": "..."}, sem texto extra.\n\n` +
              `De: ${email.remetente}\nAssunto: ${email.assunto}\nTrecho: ${email.corpo}`,
          },
        ],
      });
      const block = response.content[0];
      const text = block.type === 'text' ? block.text : '';
      const parsed = JSON.parse(text) as { categoria?: string; resumoCurto?: string };
      return {
        categoria: parsed.categoria === 'PRECISA_ATENCAO' ? 'PRECISA_ATENCAO' : 'PODE_ESPERAR',
        resumoCurto: parsed.resumoCurto ?? email.assunto,
      };
    } catch (error) {
      this.logger.warn(`LLM classification failed, falling back to PODE_ESPERAR: ${error}`);
      return { categoria: 'PODE_ESPERAR', resumoCurto: email.assunto };
    }
  }
}
