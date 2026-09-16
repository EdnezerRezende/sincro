/** Fronteira de palavra Unicode. O `\b` nativo do JS é ASCII: falha em `carnê`, `até`, `venc.`
 *  e deixa `da fatura` casar `a fatura`. Toda regex de detecção financeira passa por aqui.
 *
 *  `WB` é uma fronteira simétrica: casa tanto no lado esquerdo (transição não-letra/dígito
 *  → letra/dígito) quanto no lado direito (letra/dígito → não-letra/dígito), na mesma posição,
 *  sem depender de qual lado o `\b` original ocupava no padrão. `WB_L`/`WB_R` seguem exportados
 *  por compatibilidade, mas `wb()` substitui todo `\b` por `WB` — a paridade de ocorrência
 *  (esquerda vs. direita) é irrelevante e não deve ser usada para decidir o lado. */
export const WB_L = '(?<![\\p{L}\\p{N}])';
export const WB_R = '(?![\\p{L}\\p{N}])';
export const WB =
  '(?:(?<![\\p{L}\\p{N}])(?=[\\p{L}\\p{N}])|(?<=[\\p{L}\\p{N}])(?![\\p{L}\\p{N}]))';

export function wb(source: string, flags = 'iu'): RegExp {
  const converted = source.replace(/\\b/g, WB);
  const finalFlags = flags.includes('u') ? flags : `${flags}u`;
  return new RegExp(converted, finalFlags);
}

export function normalizar(texto: string | null | undefined): string {
  return (texto ?? '').normalize('NFC');
}
