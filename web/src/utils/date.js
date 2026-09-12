// Datas de calendário (aaaa-mm-dd) SEM passar por UTC.
// `new Date().toISOString().slice(0, 10)` converte para UTC: em BRT (UTC-3) após 21h devolve "amanhã"
// (effective_from de cenário/regra/versão nasce no futuro); em fusos positivos, à meia-noite local, devolve "ontem".
// Do mesmo modo, `new Date('2026-08-01')` é interpretado como UTC e exibido em pt-BR vira 31/07/2026.
const pad = (n) => String(n).padStart(2, '0')
const ISO_DATE = /^(\d{4})-(\d{2})-(\d{2})/
const ptBR = new Intl.DateTimeFormat('pt-BR', { day: '2-digit', month: '2-digit', year: 'numeric' })

// Date (local) → 'aaaa-mm-dd' usando os componentes locais.
export function toIso(d) { return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}` }

export function todayIso() { return toIso(new Date()) }

// 'aaaa-mm-dd' (ou timestamp ISO) → 'dd/mm/aaaa'. Vazio/nulo → ''. Sem `new Date(string)` para não deslocar o dia.
export function fmtDate(iso) {
  if (iso == null || iso === '') return ''
  const m = ISO_DATE.exec(String(iso))
  if (!m) return String(iso)
  return ptBR.format(new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3])))
}

// Timestamp ISO completo (created_at, issued_at) → data e hora locais em pt-BR.
export function fmtDateTime(ts) { return ts ? new Date(ts).toLocaleString('pt-BR') : '' }
