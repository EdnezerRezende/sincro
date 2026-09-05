import { IsISO8601, IsOptional, IsString, IsBoolean, MinLength } from 'class-validator';

export class CriarEventoDto {
  @IsString()
  @MinLength(1)
  titulo: string;

  @IsOptional()
  @IsString()
  descricao?: string;

  @IsISO8601()
  dataHoraInicio: string;

  @IsISO8601()
  dataHoraFim: string;

  @IsOptional()
  @IsBoolean()
  ehDiaInteiro?: boolean; // true se o evento é um evento de dia inteiro (all-day)
}
