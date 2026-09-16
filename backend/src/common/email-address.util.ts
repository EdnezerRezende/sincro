/** Endereço de e-mail a partir do header `From` cru (`Nome <a@b.com>`, `a@b.com` ou variações).
 *  Toda regra de detecção financeira baseada em remetente opera sobre este valor. */
export function extrairEndereco(remetente: string): string | null {
  const angle = remetente.match(/<([^<>]*@[^<>]*)>/);
  const candidato = (angle ? angle[1] : remetente).trim();
  const m = candidato.match(/[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}/i);
  return m ? m[0].toLowerCase() : null;
}

export function localPart(endereco: string): string {
  return endereco.slice(0, endereco.lastIndexOf('@'));
}

export function dominio(endereco: string): string {
  return endereco.slice(endereco.lastIndexOf('@') + 1);
}

export function rotulosDominio(endereco: string): string[] {
  return dominio(endereco).split('.').filter(Boolean);
}
