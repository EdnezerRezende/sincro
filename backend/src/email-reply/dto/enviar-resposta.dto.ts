import { IsString, MinLength } from 'class-validator';

export class EnviarRespostaDto {
  @IsString()
  @MinLength(1)
  texto: string;
}
