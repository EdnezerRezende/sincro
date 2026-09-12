import { IsIn, IsNumber, IsOptional, IsString } from 'class-validator';

export class UpdateContaDto {
  @IsOptional()
  @IsString()
  nome?: string;

  @IsOptional()
  @IsIn(['CORRENTE', 'CARTEIRA', 'POUPANCA'])
  tipo?: 'CORRENTE' | 'CARTEIRA' | 'POUPANCA';

  @IsOptional()
  @IsNumber()
  saldoAtual?: number;

  @IsOptional()
  @IsString()
  cor?: string;
}
