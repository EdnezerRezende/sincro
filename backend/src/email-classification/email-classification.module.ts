import { Module } from '@nestjs/common';
import Anthropic from '@anthropic-ai/sdk';
import { HeuristicEmailClassifier } from './heuristic-email-classifier.service';
import { LlmEmailClassifier, ANTHROPIC_CLIENT } from './llm-email-classifier.service';

@Module({
  providers: [
    HeuristicEmailClassifier,
    {
      provide: ANTHROPIC_CLIENT,
      useFactory: () => new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY }),
    },
    {
      provide: LlmEmailClassifier,
      useFactory: (client: Anthropic) => new LlmEmailClassifier(client),
      inject: [ANTHROPIC_CLIENT],
    },
  ],
  exports: [HeuristicEmailClassifier, LlmEmailClassifier],
})
export class EmailClassificationModule {}
