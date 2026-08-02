import { Injectable } from '@nestjs/common';
import {
  EmailClassification,
  EmailClassificationContext,
  EmailClassifier,
  EmailToClassify,
} from './email-classifier.interface';

const PALAVRAS_CHAVE_URGENTES = ['urgente', 'prazo', 'vencimento', 'vence', 'ação necessária', 'importante'];
const RESUMO_MAX_LENGTH = 100;

@Injectable()
export class HeuristicEmailClassifier implements EmailClassifier {
  async classify(email: EmailToClassify, _context: EmailClassificationContext): Promise<EmailClassification> {
    const assuntoLower = email.assunto.toLowerCase();
    const corpoLower = email.corpo.toLowerCase();
    const temPalavraChave = PALAVRAS_CHAVE_URGENTES.some(
      (palavra) => assuntoLower.includes(palavra) || corpoLower.includes(palavra),
    );

    return {
      categoria: temPalavraChave ? 'PRECISA_ATENCAO' : 'PODE_ESPERAR',
      resumoCurto: this.truncate(email.assunto),
    };
  }

  private truncate(subject: string): string {
    if (subject.length <= RESUMO_MAX_LENGTH) return subject;
    return `${subject.slice(0, RESUMO_MAX_LENGTH - 3)}...`;
  }
}
