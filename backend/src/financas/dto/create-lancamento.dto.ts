import { IsBoolean, IsDateString, IsIn, IsNumber, IsOptional, IsString } from 'class-validator';

export class CreateLancamentoDto {
  @IsIn(['DESPESA', 'RECEITA', 'FATURA_CARTAO'])
  tipo!: 'DESPESA' | 'RECEITA' | 'FATURA_CARTAO';

  @IsString()
  descricao!: string;

  @IsOptional()
  @IsString()
  instituicao?: string;

  @IsOptional()
  @IsNumber()
  valor?: number;

  @IsDateString()
  dataVencimento!: string;

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
