import { IsIn, IsNumber, IsOptional, IsString } from 'class-validator';

export class CreateContaDto {
  @IsString()
  nome!: string;

  @IsIn(['CORRENTE', 'CARTEIRA', 'POUPANCA'])
  tipo!: 'CORRENTE' | 'CARTEIRA' | 'POUPANCA';

  @IsNumber()
  saldoAtual!: number;

  @IsOptional()
  @IsString()
  cor?: string;
}
