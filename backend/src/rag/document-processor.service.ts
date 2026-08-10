import { Injectable, Logger, UnsupportedMediaTypeException } from '@nestjs/common';
import * as mammoth from 'mammoth';

// eslint-disable-next-line @typescript-eslint/no-require-imports
const pdfParse = require('pdf-parse') as (
  buffer: Buffer,
) => Promise<{ text: string; numpages: number }>;

export interface DocumentChunk {
  content: string;
  index: number;
  metadata: Record<string, unknown>;
}

const CHUNK_SIZE = 1500;
const CHUNK_OVERLAP = 300;

@Injectable()
export class DocumentProcessorService {
  private readonly logger = new Logger(DocumentProcessorService.name);

  async extractText(buffer: Buffer, mimeType: string): Promise<string> {
    if (mimeType === 'application/pdf') {
      return this.extractPdf(buffer);
    }
    if (
      mimeType === 'application/vnd.openxmlformats-officedocument.wordprocessingml.document' ||
      mimeType === 'application/msword'
    ) {
      return this.extractDocx(buffer);
    }
    throw new UnsupportedMediaTypeException(`Tipo de arquivo não suportado: ${mimeType}`);
  }

  private async extractPdf(buffer: Buffer): Promise<string> {
    const data = await pdfParse(buffer);
    return data.text;
  }

  private async extractDocx(buffer: Buffer): Promise<string> {
    const result = await mammoth.extractRawText({ buffer });
    return result.value;
  }

  chunkText(text: string, filename: string): DocumentChunk[] {
    const paragraphs = this.splitIntoParagraphs(text);
    const chunks: DocumentChunk[] = [];
    let currentChunk = '';
    let chunkIndex = 0;

    for (const paragraph of paragraphs) {
      if (!paragraph.trim()) continue;

      if (currentChunk.length + paragraph.length + 1 <= CHUNK_SIZE) {
        currentChunk = currentChunk ? `${currentChunk}\n${paragraph}` : paragraph;
      } else {
        if (currentChunk.trim()) {
          chunks.push({
            content: currentChunk.trim(),
            index: chunkIndex++,
            metadata: { source: filename, chunkStart: currentChunk.length },
          });
        }

        const overlap = currentChunk.slice(-CHUNK_OVERLAP);
        currentChunk = overlap ? `${overlap}\n${paragraph}` : paragraph;

        if (currentChunk.length > CHUNK_SIZE) {
          const subChunks = this.splitLongParagraph(currentChunk, filename, chunkIndex);
          chunks.push(...subChunks);
          chunkIndex += subChunks.length;
          currentChunk = subChunks.length
            ? subChunks[subChunks.length - 1].content.slice(-CHUNK_OVERLAP)
            : '';
        }
      }
    }

    if (currentChunk.trim()) {
      chunks.push({
        content: currentChunk.trim(),
        index: chunkIndex,
        metadata: { source: filename },
      });
    }

    this.logger.log(`Documento "${filename}" dividido em ${chunks.length} chunks`);
    return chunks;
  }

  private splitIntoParagraphs(text: string): string[] {
    return text
      .split(/\n{2,}/)
      .map((p) => p.replace(/\n/g, ' ').trim())
      .filter((p) => p.length > 0);
  }

  private splitLongParagraph(
    text: string,
    filename: string,
    startIndex: number,
  ): DocumentChunk[] {
    const chunks: DocumentChunk[] = [];
    let start = 0;
    let localIndex = startIndex;

    while (start < text.length) {
      const end = Math.min(start + CHUNK_SIZE, text.length);
      const content = text.slice(start, end).trim();
      if (content) {
        chunks.push({
          content,
          index: localIndex++,
          metadata: { source: filename },
        });
      }
      start += CHUNK_SIZE - CHUNK_OVERLAP;
    }

    return chunks;
  }
}
