# Validação ponto a ponto — 31/08/2026

Fechamento da rodada "completar tabelas + validar regras e tabelas + processo de atualização".

## 1. Tabelas × fontes oficiais (amostras conferidas)

22 verificações de valores conhecidos, todas OK (a única divergência inicial era expectativa errada do teste: medicamento na TIPI é alíquota 0%, não NT):

- Interestadual: SP→BA 7% (Res. 22/89), SP→RJ 12%, **ES→SP 12% / SP→ES 7%** (exceção do ES), importado 4% (Res. 13/12, origens 1/2/3/8).
- Interna: SP 18%; RJ 20% + FCP 2% (único FCP "geral").
- TIPI: 3004 = 0%; 3304.99.10 = 14,3%; cerveja 22.03 = 3,9% (alíquotas normalizadas para decimal limpo).
- CEST: 3004.90.99 → segmento 13 (medicamentos), 12 CESTs candidatos.
- Monofásico: 3004 medicamentos e 3304 perfumaria (Lei 10.147); 8471 não é.
- ST: SP×medicamento aplica (CAT 68/19); MG sem curadoria → ausente (não gera finding).
- cClassTrib: 000001→CST 000; 200003→CST 200 com redução (dataset oficial SVRS).
- Cronograma: CBS 2026 = 0,9%. CST IPI 50 = saída.

## 2. Regras

- `rules:validate`: 88 ativas válidas. `rules:test`: **207/207**. RSpec: **26/26** (inclui regressão que recria seeds do zero).
- Revisão jurídica regra a regra em `RULES_REVIEW.md` (correções da rodada anterior mantidas).

## 3. Teste com dados reais (Boiron, jul/2026 — run #34)

- Ingestão do formato do ERP (pasta com XML + **zip de nota cancelada com autorização+cancelamento**, zipada = zip dentro de zip): 578 arquivos, 0 falhas, 24 cancelamentos aplicados (inclusive quando o cancelamento chega antes da autorização).
- Zero `evaluation_errors` (todas as tabelas cobertas).
- Apontamentos: **CEST ausente em 406 itens** (Conv. 142/18 exige mesmo sem ST); **base de ICMS errada em 318 itens** (264 sem abater desconto — pagando a mais; 54 sem somar frete — pagando a menos); base IBS/CBS abaixo do piso legal em 74; 2 cancelamentos fora do prazo de 24h; 2 lacunas reais de numeração (59888…); CSTs de saída em devoluções (IPI 53, PIS 49); NFC-e sem constar do cenário.
- Silêncios corretos: ST não cobrada (522/530 notas a consumidor final — não há ST), DIFAL presente nas 6108, alíquotas 4%/18% coerentes com origem importada, cClassTrib 000001×CST 000 coerente, TIPI 0% respeitada.

## 4. Processo de atualização (implementado)

Ver `DATA_SOURCES.md` §3: sidekiq-cron (sync A-class → draft com diff; lembrete diário de revisão), `next_review_on` por classe, publicação sempre humana, regras só por nova versão com casos de teste.

## 5. Pendências conhecidas

1. `st_uf`: só SP×medicamentos — curadoria Sudeste (ou fornecedor de conteúdo).
2. `icms_internal_rate`: alíquota geral das 27 UFs + NCMs específicos do Sudeste.
3. `pis_cofins_special`: autopeças (Lei 10.485/02).
4. TIPI/CEST: reimportação é manual (classe B) — planilha/página têm formato estável, importadores prontos.
