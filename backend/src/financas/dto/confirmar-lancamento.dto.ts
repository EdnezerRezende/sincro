import { IsDateString, IsNumber, IsOptional, IsString } from 'class-validator';

export class ConfirmarLancamentoDto {
  @IsOptional()
  @IsNumber()
  valor?: number;

  @IsOptional()
  @IsDateString()
  dataVencimento?: string;

  @IsOptional()
  @IsString()
  contaId?: string;

  @IsOptional()
  @IsString()
  cartaoId?: string;
}
