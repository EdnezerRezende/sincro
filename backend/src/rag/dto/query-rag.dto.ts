import { IsIn, IsInt, IsOptional, IsString, Max, Min } from 'class-validator';
import { Type } from 'class-transformer';

export class QueryRagDto {
  @IsString()
  pergunta: string;

  @IsOptional()
  @IsIn(['tea', 'financas', 'geral'])
  categoria?: 'tea' | 'financas' | 'geral';

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(20)
  topK?: number;
}
