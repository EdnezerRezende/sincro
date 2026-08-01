import { IsBoolean, IsIn, IsInt, IsString, Length, Min } from 'class-validator';

export const RELACOES = ['PSICOLOGO', 'PSIQUIATRA', 'T.O.', 'FAMILIAR', 'OUTRO'] as const;

export class CreateTrustedContactDto {
  @IsString()
  @Length(1, 100)
  nome: string;

  @IsIn(RELACOES)
  relacao: (typeof RELACOES)[number];

  @IsString()
  @Length(8, 20)
  whatsapp: string;

  @IsInt()
  @Min(0)
  prioridade: number;

  @IsBoolean()
  consentimentoAceito: boolean;
}
