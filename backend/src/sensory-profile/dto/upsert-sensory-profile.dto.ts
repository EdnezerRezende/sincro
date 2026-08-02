import { IsObject } from 'class-validator';

export class UpsertSensoryProfileDto {
  @IsObject()
  dados: Record<string, unknown>;
}
