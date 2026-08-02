import { IsBoolean, IsIn, IsInt, IsString, Length, Matches, Min } from 'class-validator';

export const RELACOES = ['PSICOLOGO', 'PSIQUIATRA', 'T.O.', 'FAMILIAR', 'OUTRO'] as const;

export class CreateTrustedContactDto {
  @IsString()
  @Length(1, 100)
  nome: string;

  @IsIn(RELACOES)
  relacao: (typeof RELACOES)[number];

  @IsString()
  @Length(8, 20)
  @Matches(/^\+\d{10,15}$/, {
    message: 'whatsapp must start with + followed by the country code and 10-15 digits, e.g. +5511999999999',
  })
  whatsapp: string;

  @IsInt()
  @Min(0)
  prioridade: number;

  @IsBoolean()
  consentimentoAceito: boolean;
}
