import {
  dominio,
  extrairEndereco,
  rotulosDominio,
} from '../../common/email-address.util';
import { normalizar, wb } from '../../common/text-match.util';

export type TipoPadrao = 'CARTAO' | 'OUTRO';
export interface Instituicao {
  nome: string;
  tipoPadrao?: TipoPadrao;
  mapeada: boolean;
}

interface Entrada {
  dominio: string;
  nome: string;
  tipoPadrao: TipoPadrao;
}

/** ENRIQUECIMENTO, não porta de entrada: dá nome bonito e tipo padrão a quem conhecemos. A
 *  detecção (finance-email-detector.ts) funciona sem esta lista. Casamento por SUFIXO de domínio. */
const INSTITUTION_MAP: Entrada[] = [
  { dominio: 'bb.com.br', nome: 'Banco do Brasil', tipoPadrao: 'CARTAO' },
  { dominio: 'caixa.gov.br', nome: 'Caixa', tipoPadrao: 'CARTAO' },
  { dominio: 'santander.com.br', nome: 'Santander', tipoPadrao: 'CARTAO' },
  { dominio: 'itau.com.br', nome: 'Itaú', tipoPadrao: 'CARTAO' },
  { dominio: 'itaucard.com.br', nome: 'Itaú', tipoPadrao: 'CARTAO' },
  { dominio: 'bradesco.com.br', nome: 'Bradesco', tipoPadrao: 'CARTAO' },
  { dominio: 'nubank.com.br', nome: 'Nubank', tipoPadrao: 'CARTAO' },
  { dominio: 'bancointer.com.br', nome: 'Inter', tipoPadrao: 'CARTAO' },
  { dominio: 'c6bank.com.br', nome: 'C6 Bank', tipoPadrao: 'CARTAO' },
  { dominio: 'btgpactual.com', nome: 'BTG Pactual', tipoPadrao: 'CARTAO' },
  { dominio: 'neon.com.br', nome: 'Neon', tipoPadrao: 'CARTAO' },
  { dominio: 'picpay.com', nome: 'PicPay', tipoPadrao: 'CARTAO' },
  { dominio: 'mercadopago.com.br', nome: 'Mercado Pago', tipoPadrao: 'CARTAO' },
  { dominio: 'pagseguro.com.br', nome: 'PagBank', tipoPadrao: 'CARTAO' },
  { dominio: 'willbank.com.br', nome: 'Will Bank', tipoPadrao: 'CARTAO' },
  { dominio: 'xpi.com.br', nome: 'XP', tipoPadrao: 'CARTAO' },
  { dominio: 'sicoob.com.br', nome: 'Sicoob', tipoPadrao: 'CARTAO' },
  { dominio: 'sicredi.com.br', nome: 'Sicredi', tipoPadrao: 'CARTAO' },
  { dominio: 'brb.com.br', nome: 'BRB', tipoPadrao: 'CARTAO' },
  { dominio: 'bancopan.com.br', nome: 'Banco Pan', tipoPadrao: 'CARTAO' },
  { dominio: 'bancobmg.com.br', nome: 'BMG', tipoPadrao: 'CARTAO' },
  { dominio: 'pefisa.com.br', nome: 'Pefisa', tipoPadrao: 'CARTAO' },
  {
    dominio: 'cartaosamsclub.com.br',
    nome: "Sam's Club",
    tipoPadrao: 'CARTAO',
  },
  { dominio: 'midway.com.br', nome: 'Midway', tipoPadrao: 'CARTAO' },
  { dominio: 'claro.com.br', nome: 'Claro', tipoPadrao: 'OUTRO' },
  { dominio: 'vivo.com.br', nome: 'Vivo', tipoPadrao: 'OUTRO' },
  { dominio: 'tim.com.br', nome: 'TIM', tipoPadrao: 'OUTRO' },
  { dominio: 'enel.com.br', nome: 'Enel', tipoPadrao: 'OUTRO' },
  {
    dominio: 'neoenergiabrasilia.com.br',
    nome: 'Neoenergia',
    tipoPadrao: 'OUTRO',
  },
  {
    dominio: 'faturaneoenergiabrasilia.com.br',
    nome: 'Neoenergia',
    tipoPadrao: 'OUTRO',
  },
  { dominio: 'light.com.br', nome: 'Light', tipoPadrao: 'OUTRO' },
  { dominio: 'cpfl.com.br', nome: 'CPFL', tipoPadrao: 'OUTRO' },
  { dominio: 'cemig.com.br', nome: 'Cemig', tipoPadrao: 'OUTRO' },
  { dominio: 'sabesp.com.br', nome: 'Sabesp', tipoPadrao: 'OUTRO' },
  { dominio: 'comgas.com.br', nome: 'Comgás', tipoPadrao: 'OUTRO' },
  { dominio: 'starlink.com', nome: 'Starlink', tipoPadrao: 'OUTRO' },
  { dominio: 'portoseguro.com.br', nome: 'Porto Seguro', tipoPadrao: 'OUTRO' },
];

/** Radicais de concessionária, como prefixo/sufixo de um rótulo do domínio (`^gas` e `^net` ficaram
 *  de fora: casavam `gastrobar`/`netflix`). Só decide tipoPadrao de desconhecidos. */
export const UTILIDADE_RE =
  /^(energia|eletr|luz|agua|saneamento|telecom)|(energia|eletrica|luz|agua|gas)$/i;
const CONTA_DE_RE = wb(
  '\\bconta de (luz|energia|[áa]gua|g[áa]s|internet|telefone)\\b',
);

const GENERIC_SECOND_LEVEL = new Set(['com', 'net', 'org', 'gov', 'edu', 'co']);
const GENERIC_SUBDOMAIN_LABELS = new Set([
  'mail',
  'email',
  'e',
  'news',
  'notificacoes',
  'notificacao',
  'mailer',
  'info',
  'no-reply',
  'noreply',
]);

/** Nome de melhor esforço para um remetente FORA do `INSTITUTION_MAP`: extrai o rótulo do
 *  domínio, descarta o sufixo público ("com"/"com.br"/...) e rótulos genéricos de subdomínio
 *  de mailer ("mail", "e", "notificacoes", ...), chegando na marca registrável
 *  (`mail.meubanco.com` → "Meubanco", não "Mail"). */
export function deriveInstituicaoFromDomain(endereco: string): string | null {
  const labels = rotulosDominio(endereco.toLowerCase());
  if (labels.length < 2) return null;
  const publicSuffixLength =
    labels.length > 2 && GENERIC_SECOND_LEVEL.has(labels[labels.length - 2])
      ? 2
      : 1;
  const candidates = labels.slice(0, labels.length - publicSuffixLength);
  if (candidates.length === 0) return null;
  const significant =
    candidates.find((l) => !GENERIC_SUBDOMAIN_LABELS.has(l)) ??
    candidates[candidates.length - 1];
  return significant.charAt(0).toUpperCase() + significant.slice(1);
}

export function resolverInstituicao(
  remetente: string,
  assunto: string,
): Instituicao {
  const endereco = extrairEndereco(remetente);
  if (!endereco)
    return { nome: 'Desconhecida', tipoPadrao: undefined, mapeada: false };
  const dom = dominio(endereco);
  const entrada = INSTITUTION_MAP.find(
    (e) => dom === e.dominio || dom.endsWith(`.${e.dominio}`),
  );
  if (entrada)
    return {
      nome: entrada.nome,
      tipoPadrao: entrada.tipoPadrao,
      mapeada: true,
    };

  const utilidade =
    rotulosDominio(endereco).some((l) => UTILIDADE_RE.test(l)) ||
    CONTA_DE_RE.test(normalizar(assunto));
  return {
    nome: deriveInstituicaoFromDomain(endereco) ?? 'Desconhecida',
    tipoPadrao: utilidade ? 'OUTRO' : undefined,
    mapeada: false,
  };
}
