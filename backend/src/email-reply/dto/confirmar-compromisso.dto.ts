import { IsIn, IsISO8601, IsInt, IsString, MinLength } from 'class-validator';

export class ConfirmarCompromissoDto {
  @IsString()
  @MinLength(1)
  tituloCompromisso: string;

  @IsISO8601()
  dataHoraLimite: string;

  @IsInt()
  @IsIn([60, 1440])
  antecedenciaMinutos: number;
}
