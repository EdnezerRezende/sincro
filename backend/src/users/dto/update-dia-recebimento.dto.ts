import { IsInt, IsOptional, Max, Min } from 'class-validator';

export class UpdateDiaRecebimentoDto {
  @IsOptional()
  @IsInt()
  @Min(1)
  @Max(31)
  diaRecebimento: number | null;
}
