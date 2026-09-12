import { IsBoolean, IsDateString, IsIn, IsNumber, IsOptional, IsString } from 'class-validator';

export class UpdateLancamentoDto {
  @IsOptional()
  @IsIn(['DESPESA', 'RECEITA', 'FATURA_CARTAO'])
  tipo?: 'DESPESA' | 'RECEITA' | 'FATURA_CARTAO';

  @IsOptional()
  @IsString()
  descricao?: string;

  @IsOptional()
  @IsString()
  instituicao?: string;

  @IsOptional()
  @IsNumber()
  valor?: number;

  @IsOptional()
  @IsDateString()
  dataVencimento?: string;

  @IsOptional()
  @IsDateString()
  dataCompetencia?: string;

  @IsOptional()
  @IsString()
  contaId?: string;

  @IsOptional()
  @IsString()
  cartaoId?: string;

  @IsOptional()
  @IsBoolean()
  isPago?: boolean;
}
