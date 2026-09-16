/** Fronteira de palavra Unicode. O `\b` nativo do JS é ASCII: falha em `carnê`, `até`, `venc.`
 *  e deixa `da fatura` casar `a fatura`. Toda regex de detecção financeira passa por aqui. */
export const WB_L = '(?<![\\p{L}\\p{N}])';
export const WB_R = '(?![\\p{L}\\p{N}])';

export function wb(source: string, flags = 'iu'): RegExp {
  let i = 0;
  const converted = source.replace(/\\b/g, () => (i++ % 2 === 0 ? WB_L : WB_R));
  const finalFlags = flags.includes('u') ? flags : `${flags}u`;
  return new RegExp(converted, finalFlags);
}

export function normalizar(texto: string | null | undefined): string {
  return (texto ?? '').normalize('NFC');
}
