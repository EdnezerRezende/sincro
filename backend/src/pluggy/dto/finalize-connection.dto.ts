import { IsString, MinLength } from 'class-validator';

export class FinalizeConnectionDto {
  @IsString()
  @MinLength(1)
  itemId: string;
}
