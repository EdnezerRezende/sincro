import { IsNumberString } from 'class-validator';

/** Query params chegam sempre como string, mesmo quando representam números — daí `IsNumberString`
 *  em vez de `IsInt`/`@Type(() => Number)`: o `ValidationPipe` global não roda com `transform: true`
 *  (ver main.ts), então o valor que o controller recebe é a string original, não uma instância
 *  transformada. O parsing para número e a validação de faixa (`ano` razoável, `mes` entre 1-12)
 *  acontecem explicitamente no controller — decoradores como `@Min`/`@Max` do class-validator só
 *  validam valores `typeof === 'number'`, e como não há transform aqui o valor é sempre string.
 *
 *  `@IsNumberString()` garante que os valores são strings compostas apenas de dígitos (ou
 *  com sinais de negativo opcional), rejeitando valores malformados no ValidationPipe antes
 *  do controller ser acionado. */
export class EventosMesQueryDto {
  @IsNumberString()
  ano: string;

  @IsNumberString()
  mes: string;
}
