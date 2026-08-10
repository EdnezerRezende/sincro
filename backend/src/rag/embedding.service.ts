import { Injectable, Logger } from '@nestjs/common';
import OpenAI from 'openai';

@Injectable()
export class EmbeddingService {
  private readonly logger = new Logger(EmbeddingService.name);
  private client: OpenAI | undefined;
  private readonly MODEL = 'text-embedding-3-small';
  private readonly DIMENSIONS = 1536;

  // OPENAI_API_KEY is optional at boot: RAG is not a core feature yet, so the whole backend
  // shouldn't fail to start over it. The client is only constructed (and only throws if the key
  // is missing) when a RAG feature actually gets used.
  private getClient(): OpenAI {
    if (!process.env.OPENAI_API_KEY) {
      throw new Error(
        'OPENAI_API_KEY não configurada — recursos de RAG (embeddings) estão indisponíveis.',
      );
    }
    this.client ??= new OpenAI({ apiKey: process.env.OPENAI_API_KEY });
    return this.client;
  }

  async generateEmbedding(text: string): Promise<number[]> {
    const normalized = text.replace(/\n+/g, ' ').trim();
    const response = await this.getClient().embeddings.create({
      model: this.MODEL,
      input: normalized,
      dimensions: this.DIMENSIONS,
    });
    return response.data[0].embedding;
  }

  async generateEmbeddings(texts: string[]): Promise<number[][]> {
    if (texts.length === 0) return [];

    const normalized = texts.map((t) => t.replace(/\n+/g, ' ').trim());
    const response = await this.getClient().embeddings.create({
      model: this.MODEL,
      input: normalized,
      dimensions: this.DIMENSIONS,
    });

    return response.data
      .sort((a, b) => a.index - b.index)
      .map((d) => d.embedding);
  }

  formatEmbeddingForPg(embedding: number[]): string {
    return `[${embedding.join(',')}]`;
  }
}
