import { IsIn, IsOptional } from 'class-validator';

export class UploadDocumentDto {
  @IsOptional()
  @IsIn(['tea', 'financas', 'geral'])
  categoria?: 'tea' | 'financas' | 'geral';
}
