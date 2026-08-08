import { IsBoolean, IsIn, IsOptional, IsString, Length } from 'class-validator';
import { CATEGORIAS_CARTAO } from './categorias-cartao';

export class UpdateGroundingCardDto {
  @IsString()
  @Length(1, 100)
  titulo: string;

  @IsIn(CATEGORIAS_CARTAO)
  categoria: (typeof CATEGORIAS_CARTAO)[number];

  @IsString()
  @Length(1, 2000)
  conteudo: string;

  @IsOptional()
  @IsBoolean()
  ativo?: boolean;
}
