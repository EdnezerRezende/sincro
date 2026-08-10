import { Injectable, Logger } from '@nestjs/common';
import Anthropic from '@anthropic-ai/sdk';
import { HybridSearchService, ChunkResult } from './hybrid-search.service';

export interface RagResponse {
  resposta: string;
  fontes: Array<{
    documentoId: string;
    trecho: string;
    score: number;
    metadados: Record<string, unknown> | null;
  }>;
  totalFontesUsadas: number;
}

const SYSTEM_PROMPT = `Você é um assistente especializado em apoio a pessoas com Transtorno do Espectro Autista nível 1 (TEA), Transtorno do Déficit de Atenção (TDA) e Transtorno do Déficit de Atenção com Hiperatividade (TDAH), com foco também em educação financeira adaptada para essas necessidades.

Suas respostas devem:
- Ser claras, diretas e objetivas
- Usar linguagem simples e acessível, sem jargões desnecessários
- Respeitar as necessidades específicas do público (rotinas, previsibilidade, clareza)
- Basear-se apenas nas informações fornecidas no contexto
- Indicar honestamente quando não há informação suficiente no contexto

Caso a pergunta não esteja relacionada ao contexto fornecido, responda de forma breve e oriente o usuário a buscar informações específicas.`;

@Injectable()
export class RagService {
  private readonly logger = new Logger(RagService.name);
  private readonly anthropic: Anthropic;

  constructor(private readonly hybridSearch: HybridSearchService) {
    this.anthropic = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });
  }

  async query(
    pergunta: string,
    categoria?: string,
    topK = 6,
  ): Promise<RagResponse> {
    this.logger.log(`RAG query: "${pergunta.slice(0, 60)}..." [categoria: ${categoria ?? 'todas'}]`);

    const chunks = await this.hybridSearch.search(pergunta, topK, categoria);

    if (chunks.length === 0) {
      return {
        resposta:
          'Não encontrei informações relevantes na base de conhecimento para responder sua pergunta. Por favor, verifique se os documentos corretos foram carregados.',
        fontes: [],
        totalFontesUsadas: 0,
      };
    }

    const context = this.buildContext(chunks);

    const userMessage = `Contexto da base de conhecimento:\n\n${context}\n\n---\n\nPergunta: ${pergunta}`;

    const message = await this.anthropic.messages.create({
      model: 'claude-opus-4-5',
      max_tokens: 1024,
      system: SYSTEM_PROMPT,
      messages: [{ role: 'user', content: userMessage }],
    });

    const resposta =
      message.content[0].type === 'text' ? message.content[0].text : '';

    return {
      resposta,
      fontes: chunks.map((c) => ({
        documentoId: c.documentoId,
        trecho: c.conteudo.slice(0, 200) + (c.conteudo.length > 200 ? '...' : ''),
        score: Math.round(c.score * 10000) / 10000,
        metadados: c.metadados,
      })),
      totalFontesUsadas: chunks.length,
    };
  }

  private buildContext(chunks: ChunkResult[]): string {
    return chunks
      .map((chunk, i) => `[Trecho ${i + 1}]\n${chunk.conteudo}`)
      .join('\n\n');
  }
}
