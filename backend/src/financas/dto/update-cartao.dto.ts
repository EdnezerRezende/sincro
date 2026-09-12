import { IsInt, IsNumber, IsOptional, IsString, Max, Min } from 'class-validator';

export class UpdateCartaoDto {
  @IsOptional()
  @IsString()
  nome?: string;

  @IsOptional()
  @IsInt()
  @Min(1)
  @Max(31)
  diaFechamento?: number;

  @IsOptional()
  @IsInt()
  @Min(1)
  @Max(31)
  diaVencimento?: number;

  @IsOptional()
  @IsNumber()
  limiteTotal?: number;

  @IsOptional()
  @IsString()
  cor?: string;
}
