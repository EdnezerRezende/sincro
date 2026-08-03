import { Module } from '@nestjs/common';
import { PluggyApiClient } from './pluggy-api-client.service';

@Module({
  providers: [PluggyApiClient],
  exports: [PluggyApiClient],
})
export class PluggyModule {}
