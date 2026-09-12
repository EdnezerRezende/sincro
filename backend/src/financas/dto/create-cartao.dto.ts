import { IsInt, IsNumber, IsOptional, IsString, Max, Min } from 'class-validator';

export class CreateCartaoDto {
  @IsString()
  nome!: string;

  @IsInt()
  @Min(1)
  @Max(31)
  diaFechamento!: number;

  @IsInt()
  @Min(1)
  @Max(31)
  diaVencimento!: number;

  @IsNumber()
  limiteTotal!: number;

  @IsOptional()
  @IsString()
  cor?: string;
}
