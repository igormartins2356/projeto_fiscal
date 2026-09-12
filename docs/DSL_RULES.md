# DSL de regras — especificação

> Define o formato das regras (dado em JSONB), os operadores, o contexto disponível por escopo, as primitivas nativas, o cenário resolvido, os casos de teste e as sobreposições por firma/cliente. Complementa `ARQUITETURA.md` (seções 3 e 13) e usa o vocabulário de `CANONICO.md`.
>
> Versão da DSL: **`dsl_version: 1`**. `dsl_version` é coluna da regra (entra na `definition`) e a validação estática recusa qualquer valor diferente de 1 — o motor só sabe avaliar essa. Adicionar operador = minor; mudar semântica = major (regras antigas continuam avaliadas pela versão declarada).

---

## 1. Anatomia de uma regra

```jsonc
{
  "dsl_version": 1,
  "code": "ICMS.RATE.INTERSTATE",           // identidade estável; PREFIX.SUBJECT.DETAIL, maiúsculas
  "version": 2,                             // incrementa a cada publicação do mesmo code
  "title": "Alíquota interestadual de ICMS",
  "scope": "item",                          // item | document | cross_document | period | scenario
  "effective_from": "2013-01-01",
  "effective_until": null,
  "applies_when": { /* condição — seção 3 */ },
  "assert":       { /* condição — seção 3 */ },   // OU
  "primitive":    { "name": "duplicate_document", "params": {} },
  "severity": "error",                      // error | warning | info
  "message": "Alíquota {{item.icms.rate}}% divergente da esperada {{expected}}% para {{doc.operation.origin_uf}}→{{doc.operation.destination_uf}}.",
  "explanation": "Texto longo em linguagem de contador (markdown).",
  "legal_references": [{"label": "Resolução SF 22/1989", "url": null}],
  "suggested_fix": "Ajustar a alíquota interestadual no cadastro de tributação do ERP.",
  "params": {"tolerance": "0.01"},
  "tags": ["icms", "interstate"],
  "group_by": ["item.icms.rate", "expected"]    // agrupamento no painel (seção 8)
}
```

Exatamente um de `assert` ou `primitive` é obrigatório. `applies_when` é opcional (ausente = aplica a tudo do escopo).

Semântica: para cada **alvo** do escopo, se `applies_when` é verdadeiro e `assert` é **falso** → gera `finding`. Se `assert` não pode ser avaliado (campo ausente sem operador `absent`/`present` cobrindo) → **não gera finding** e registra `evaluation_error` no run (regra mal escrita nunca vira erro para o contador).

### 1.1 Severidades

| Severidade | Significado para o contador |
|---|---|
| `error` | Documento/escrituração está errado; risco de autuação ou rejeição |
| `warning` | Provavelmente errado; depende de contexto que o sistema não tem |
| `info` | Não é erro; chama atenção (benefício não utilizado, campo opcional vazio) |
| `blocking` | Reservado ao sistema (ingestão): XML inválido, homologação, arquivo ilegível. Não usável em regras |

---

## 2. Valores, tipos e caminhos

- **Caminho** (`field`): string pontilhada resolvida no contexto do escopo (`item.icms.rate`, `doc.recipient.uf`, `scenario.tax_regime`). Índices em listas: `doc.references[0].resolved`; quantificadores em 3.3.
- **Tipos**: `string`, `decimal` (string decimal do canônico, comparado como `BigDecimal`), `int`, `bool`, `date`, `datetime`, `list`, `absent`.
- **Coerção**: em `gt/gte/lt/lte/between`, dois lados numéricos comparam como `BigDecimal` e, se um dos lados for data/hora, os dois viram data. Fora disso cai no `<=>` do Ruby: **duas strings comparam lexicograficamente** (`"5102" < "5405"` é verdadeiro e não é erro) e tipos realmente incomparáveis (string × número, string × bool) → `evaluation_error`. `eq` entre `decimal` e string numérica compara numericamente (`"18.00" == "18"`).
- **Literais**: qualquer JSON. Referência a outro campo: `{"ref": "item.icms.expected_amount"}`. Expressão: `{"calc": "..."}` (seção 4).
- **Ausência**: campo inexistente é `absent`. `present`/`absent` respondem *sobre* a ausência; `eq`, `neq` e `in` **toleram** o campo ausente (`eq` só é verdadeiro contra `null`, `neq` é verdadeiro contra qualquer valor não nulo, `in` só é verdadeiro se `null` estiver na lista) — é isso que permite `{"field": "doc.operation.final_consumer", "op": "eq", "value": false}` não virar erro em nota sem o campo. **Todo o resto** (`not_in`, `gt`/`gte`/`lt`/`lte`, `between`, `approx`, `regex`, `starts_with`/`ends_with`/`contains`, `length_*`, `empty`/`not_empty`) → `evaluation_error`: guarde o campo com `present` (no `applies_when`, ou dentro de um `any` com `absent`) antes de usá-los. `value` que se resolve para ausente (ref/lookup sem linha) também é `evaluation_error`.

---

## 3. Condições

### 3.1 Comparação

```jsonc
{"field": "item.icms.cst", "op": "in", "value": ["10", "30", "70"]}
{"field": "item.icms.amount", "op": "approx", "value": {"ref": "item.icms.expected_amount"}, "tolerance": {"param": "tolerance"}}
```

| `op` | Aridade do `value` | Notas |
|---|---|---|
| `eq`, `neq` | escalar | |
| `in`, `not_in` | lista | |
| `gt`, `gte`, `lt`, `lte` | número/data | |
| `between` | `[min, max]` inclusivo | |
| `approx` | número + `tolerance` (absoluta) ou `tolerance_pct` | uso padrão para valores calculados |
| `present`, `absent` | — | |
| `regex` | string (RE2-compatível, sem backtracking catastrófico) | |
| `starts_with`, `ends_with`, `contains` | string | `contains` também para listas |
| `length_eq`, `length_between` | int / `[min,max]` | strings e listas |
| `empty`, `not_empty` | — | listas e strings |

### 3.2 Lógicos

```jsonc
{"all": [c1, c2]}      // AND
{"any": [c1, c2]}      // OR
{"not": c}
{"if": c, "then": c2, "else": c3}   // else opcional (ausente = true)
```

### 3.3 Quantificadores sobre listas

```jsonc
{"every": "doc.items", "as": "it", "where": {"field": "it.product.cfop", "op": "starts_with", "value": "5"}}
{"some":  "doc.references", "as": "r", "where": {"field": "r.resolved", "op": "eq", "value": true}}
{"count": "doc.items", "where": {...}, "op": "gte", "value": 2}
{"none":  "period.documents", "where": {...}}
```

### 3.4 Lookup no Catalog

```jsonc
{"lookup": "icms_interstate_rate",
 "key": [{"ref": "doc.operation.origin_uf"}, {"ref": "doc.operation.destination_uf"}, {"ref": "item.icms.origin_category"}],
 "as": "expected"}
```

- Resolve a versão da tabela vigente em `doc.reference_date` **já com as sobreposições** de firma/cliente aplicadas (seção 9).
- Resultado fica disponível como variável (`expected`) para o `assert`, `message` e `group_by`. Lookup sem linha → `absent` (a regra decide com `present`/`absent`).
- `lookup` pode aparecer numa lista `"let": [...]` no topo da regra, avaliada antes de `applies_when`:

```jsonc
"let": [
  {"lookup": "icms_interstate_rate", "key": [...], "as": "expected"},
  {"calc": "item.net_amount * (1 - item.icms.base_reduction_pct / 100)", "as": "expected_base"}
]
```

---

## 4. Expressões (`calc`)

Mini-linguagem aritmética, sem efeitos colaterais, avaliada em `BigDecimal`:

- Operadores: `+ - * / %`, parênteses, comparação (`== != < <= > >=`), `and or not`.
- Funções: `round(x, n)` (`ROUND_HALF_UP`), `abs`, `min`, `max`, `sum(list.path)`, `coalesce(a, b)`, `year(date)`, `month(date)`, `days_between(a, b)`, `len(list)`, `opt(caminho)`.
- `opt(item.icms.rate)` devolve `null` em vez de estourar quando o caminho está **ausente** — é o par de `coalesce` para campo opcional: `coalesce(opt(by_ncm.rate), geral.rate)`. Sem `opt`, identificador ausente vira `evaluation_error` (que é o certo quando o campo deveria existir). `sum` e `opt` recebem o caminho como identificador, não como string.
- Identificadores = caminhos do contexto e variáveis de `let`/`params` (`params.tolerance`).
- Sem loops, sem strings mutáveis, sem acesso a nada fora do contexto. Parser próprio (não `eval`), reconstruído a cada avaliação (expressões são curtas; não há cache de AST).

Exemplo (base de ICMS): `round(item.net_amount * (1 - coalesce(item.icms.base_reduction_pct, 0) / 100), 2)`

---

## 5. Contexto por escopo

| Escopo | Alvo (1 finding por…) | Variáveis |
|---|---|---|
| `item` | item | `item`, `doc`, `scenario`, `params` |
| `document` | documento | `doc` (com `doc.items[]`), `scenario`, `params` |
| `cross_document` | definido pela primitiva | `period`, `scenario`, `params` |
| `period` | definido pela primitiva | `period`, `fiscal_file`, `scenario`, `params` |
| `scenario` | cenário (1 finding por regra) | `period`, `scenario`, `stats`, `params` |

`period` = `{documents[], events[], invalidations[]}` — todos os documentos fiscais do período do run (o recorte de datas é do run, não do contexto). Documentos `cancelled`/`denied`/`rejected` ficam em `period.documents` com o status, para que a primitiva possa raciocinar sobre eles; regras de escopo `item`/`document` **não rodam** nesses documentos (filtro do motor, não da regra).

`fiscal_file` (escopo `period`) = o arquivo da EFD do período já indexado por documento: `{info: {id, errors[]}, c100: [{record_id, line, access_key, fields{}, c170[], c190[]}]}`.

Escopos `cross_document`, `period` e `scenario` são avaliados **uma vez por run**, com as regras/tabelas/cenário vigentes no último dia do período (ARQUITETURA §3.4); os escopos `item` e `document` são avaliados com a resolução da data de emissão de cada documento.

`stats` (escopo `scenario`) é um objeto `Audit::Stats` com `distribution(path)`, `share(condition)`, `count(condition)` e `unevaluable(condition)`. **A DSL ainda não tem sintaxe de chamada**: `stats` só serve a primitivas; uma condição que escreva `stats.distribution` como caminho não avalia. Hoje `scenario_field_disagreement` calcula a própria fração e expõe `share_pct`, `matching_items`, `evaluated_items`, `unevaluable_items` e `total_items` como variáveis da mensagem.

---

## 6. Primitivas nativas (v1)

Primitivas são classes Ruby registradas em `Rules::Primitives`, sem valor fiscal embutido; tudo que é "esperado" vem de `params` ou de `let`. Cada primitiva declara `scope`, `params_schema` e o formato do `finding` que emite.

Params **sem default** são valor fiscal (prazo, COD_SIT, modelo, mapa de CFOP): a regra é obrigada a informá-los e a omissão vira `evaluation_error`, nunca um palpite do código.

| Nome | Escopo | Params (default entre parênteses) | Emite finding por |
|---|---|---|---|
| `items_sum_matches_totals` | document | `fields[]` (`products, icms_base, icms, icms_st, ipi, pis, cofins`), `tolerance` (`0.01`) | campo divergente |
| `duplicate_document` | cross_document | `match_on` (`number_series_cnpj` \| `access_key`), `only_authorized` (`true`) | par duplicado |
| `numbering_gap` | cross_document | `max_gap_ignored` (`0`), `consider_invalidations` (`true`) | intervalo faltante por série |
| `numbering_order` | cross_document | `tolerance_days` (`0`) | nota cujo número é maior que o da anterior mas foi emitida antes (série fora de ordem) |
| `return_references_original` | cross_document | `check` (`all` \| `missing` \| `exceeds` \| `mirror`), `tolerance` (`0.0001`), `mirror_fields[]` (`icms.situation_code, icms.rate`), **`cfop_mirror{}`** (CFOP da venda → CFOPs de devolução aceitos; **obrigatório** em `mirror`) | devolução com problema |
| `event_consistency` | cross_document | `check` (`all` \| `late_cancellation` \| `correction_on_cancelled` \| `cancelled_with_return`), **`cancellation_deadline_hours`** (obrigatório quando o check alcança `late_cancellation`) | nota com evento incoerente |
| `scenario_field_disagreement` | scenario | **`field`** (caminho *dentro* do cenário, sem o prefixo `scenario.`), `when_field_is` (`false`), **`evidence`** (condição avaliada no escopo `item`), `threshold` (`0.2`) | cenário contradito pelas notas (1 finding por regra) |
| `sped_document_reconciliation` | period | `check` (`presence` \| `cancelled` \| `analytic` \| `values`), **`models[]`** (COD_MOD aceitos no C100), **`own_issue_ind_emit`** (IND_EMIT de emissão própria), **`cancelled_cod_sit[]`**, **`analytic_cod_sit[]`**, **`values_cod_sit[]`** (conforme o `check`), `compare_fields{}` (campo da EFD → caminho do total), `tolerance` (`0.01`) | nota ausente/sobrando, COD_SIT errado, C100 sem C190, total divergente |
| `sped_item_reconciliation` | period | `compare_fields{}` (campo do C170 → caminho do item; default CFOP, ALIQ_ICMS, VL_BC_ICMS, VL_ICMS), `tolerance` (`0.02`) | item divergente (C170 × item) |
| `sped_c190_consistency` | period | `tolerance` (`0.05`) | C190 que não consolida os C170 do mesmo C100 por (CST, CFOP, alíquota) |
| `sped_structure` | period | — | erro de leiaute registrado pelo parser da EFD (linha + registro) |

Cada primitiva declara em `vars` as variáveis que expõe para `message` e `group_by` (a validação estática confere: `{{problem}}`, `{{line}}`, `{{share_pct}}`… só existem se estiverem lá). SINTEGRA ainda **não** tem primitiva — a conciliação 50/54 é fase posterior.

Adicionar primitiva é deploy; deve ser raro. Se uma regra "precisa" de primitiva nova, primeiro verificar se `let` + quantificadores resolvem.

---

## 7. Cenário resolvido (`scenario`)

O motor nunca lê `tax_scenarios` cru: recebe o `data` da versão **publicada e vigente** na data (`Scenario::TaxScenario.resolve(client, date)`), sem o envelope (`version_id`, `effective_from` e afins ficam no snapshot do run, não no contexto da regra). Sem cenário publicado na data, as regras que leem `scenario.*` não rodam e o run registra um `evaluation_error` explicando.

```jsonc
{
  "tax_regime": "simples_nacional",          // simples_nacional | simples_nacional_excess | lucro_presumido | lucro_real | mei
  "simples_annex": "I",                      // opcional
  "uf": "SP", "city_code": "3550308",
  "icms_taxpayer": true, "ipi_taxpayer": false, "iss_taxpayer": false,
  "activity": ["commerce"],                  // commerce | industry | service | rural | mixed
  "cnae": {"primary": "4711302", "secondary": []},
  "sells_to_final_consumer": true, "uses_nfce": true, "exports": false, "imports": false,
  "st": {"source": "catalog",                // catalog | manual
         "applies": false,                    // o cliente opera com ST? (é o campo que `SCENARIO.ST.DISAGREEMENT` desconfia)
         "overrides": [{"ncm": "2202*", "applies": false, "legal_basis": "...", "effective_from": "..."}]},
  "benefits": [{"kind": "reduced_base", "pct": "33.33", "applies_to": {"ncm": ["0402*"]}, "legal_basis": "...", "effective_from": "...", "effective_until": null}],
  "pis_cofins": {"regime": "simples"},       // simples | cumulative | non_cumulative
  "ibs_cbs": {"regime": "regular"},          // regular | simples_nacional_opt_in
  "ie_st": "...", "notes": "..."             // cadastrais; sem uso em regra
}
```

Wildcards `*` em NCM/CFOP são aceitos onde a doc marcar. `scenario.benefits` e `scenario.st.overrides` são consultáveis com quantificadores (`some scenario.benefits where …`). Exceção de ST e benefício só entram publicados com **base legal e vigência** (`Scenario::Validator`) — sem isso o motor estaria aplicando "regra fiscal" sem fonte.

---

## 8. Findings

```jsonc
{
  "rule_id": 913, "rule_code": "ICMS.RATE.INTERSTATE", "rule_source": "platform",   // platform | firm | client
  "audit_run_id": 771, "client_id": 118, "document_id": 9981, "item_number": 3, "fiscal_record_id": null,
  "severity": "error", "scope": "item", "shadow": false,
  "message": "…renderizada…",
  "evidence": {"item.icms.rate": "12.00", "expected": "7.00", "doc.operation.origin_uf": "SP", "doc.operation.destination_uf": "BA"},
  "xml_path": null,
  "group_key": "12.00|7.00",
  "dedupe_key": "ICMS.RATE.INTERSTATE|9981|3||12.00,7.00,SP,BA",
  "state": "open", "state_note": null        // open | justified | false_positive | fixed | ignored
}
```

- `evidence` = todos os campos referenciados em `applies_when`/`assert`/`message` com seus valores, mais o que a primitiva devolveu; é o que dá auditabilidade.
- `fiscal_record_id` aponta a linha do arquivo da EFD quando o finding nasce de primitiva `period`.
- `shadow` marca finding de regra em sombra: fica fora do que o contador vê.
- `xml_path` (coluna existente, **ainda não preenchida**) reservado para o caminho no XML — depende de o parser guardar a origem por campo.
- `group_key` agrupa no painel ("14 notas com alíquota 12% onde se esperava 7%").
- `dedupe_key` = `code|document_id|item_number|fiscal_record_id|valores da evidência`, estável entre runs: permite carregar `state` do run anterior (uma justificativa não some ao reprocessar). Só `justified`, `false_positive` e `ignored` são herdados — `fixed` não, porque se o mesmo `dedupe_key` reapareceu, o problema voltou.

---

## 9. Sobreposições (firma / cliente)

Duas famílias, ambas com vigência e com autoria obrigatória (`created_by`, `justification`).

### 9.1 Sobre regra (`rule_overrides`)

```jsonc
{
  "rule_code": "ICMS.RATE.INTERNAL",
  "source_type": "client", "source_id": 118,
  "effective_from": "2026-01-01", "effective_until": null,
  "override_action": "adjust",              // disable | enable | adjust | replace
  "patch": {                                // só para adjust; campos aceitos: severity, params, assert, applies_when, message, let
    "severity": "info",
    "assert": {"field": "item.icms.rate", "op": "approx", "value": {"ref": "expected_rate"}, "tolerance": "0.5"}   // `expected_rate` vem do `let` da regra base
  },
  "justification": "Regime especial nº … concede alíquota reduzida; o escritório acompanha sem apontar erro.",
  "created_by": 7
}
```

- `disable`: regra não roda para o alvo.
- `adjust`: substitui os campos listados no `patch` — `severity`, `params`, `assert`, `applies_when`, `message` e `let` (trocar a tabela consultada ou o esperado costuma ser exatamente o que o escritório quer ajustar). O `code` e o `scope` nunca mudam.
- `replace`: corpo completo de regra própria com `code` prefixado (`FIRM123.ICMS.…`); só firma, fase posterior.
- Precedência: `client > firm > platform`. Override de cliente sobre uma regra que a firma desativou reativa? **Não**: `disable` na firma vence, exceto se o override de cliente for `action: enable` (explícito).

### 9.2 Sobre tabela (`reference_row_overrides`)

```jsonc
{
  "table_code": "icms_internal_rate",
  "source_type": "client", "source_id": 118,
  "key": ["SP", "22021000"],
  "data": {"rate": "12.00", "reduced_base_pct": null},
  "effective_from": "2026-03-01", "effective_until": null,
  "legal_basis": "Decreto …", "justification": "…", "created_by": 7
}
```

`lookup` resolve: linha do cliente vigente → linha da firma → linha da plataforma. Painel avisa quando a base publica nova versão que conflita com um override ativo.

### 9.3 Snapshot no run

`audit_runs.snapshot` guarda `{rule_version_ids[], rule_override_ids[], reference_version_ids[], reference_row_override_ids[], scenario_version_id, dsl_version, engine_version}`. Qualquer finding é reproduzível a partir do snapshot.

---

## 10. Casos de teste de regra

Cada regra tem ≥ 1 caso que **dispara** e ≥ 1 que **não dispara** para ser publicável.

```jsonc
{
  "rule_code": "CEST.REQUIRED", "rule_version": 1,
  "name": "dispara: NCM com CEST esperado e item sem CEST",
  "reference_date": "2026-03-14",
  "scenario": {"tax_regime": "simples_nacional", "uf": "SP"},         // parcial; resto vem de um default
  "input": {"kind": "canonical", "document": { ...recorte canônico... }},   // ou {"kind": "xml", "fixture": "spec/fixtures/nfe/sale_return_csosn_102.xml"}
  // o documento do caso passa pelas MESMAS derivações do run (`derive: false` desliga, para testar canônico cru)
  // escopos cross_document/period/scenario: "documents": [ {...}, {...} ], "events": [ {access_key, event: {kind, occurred_at}} ], "invalidations": [ {model, series, first_number, last_number} ]
  // escopo period: "fiscal_file": {"info": {...}, "c100": [...]} e "monitored_cnpj"
  "catalog": {"cest": [{"key": ["22021000"], "data": {"cest": ["0300700"]}}]},   // opcional, sobrepõe o catálogo real no teste
  "expect": {"findings": [{"item_number": 1, "severity": "error", "evidence": {"item.product.ncm": "22021000"}}]}   // ou {"findings": []}
}
```

- Rodam na publicação (bloqueiam), no CI (`bin/rails rules:test` roda todos os casos de todas as regras; `bin/rails rules:validate` faz a validação estática) e sob demanda no painel.
- Documentos canônicos de teste são construídos por `lib/rule_case_builder.rb` (`RuleCaseBuilder.doc(item:, doc:, normal:)`); a seed `db/seeds/06_rule_test_cases.rb` cobre todas as regras com ≥1 caso que dispara e ≥1 que não dispara.
- Fixtures XML reais são anonimizadas (CNPJ/nomes/endereços substituídos) por script antes de entrar no repositório.

---

## 11. Ciclo de vida e publicação

`draft → testing → shadow → published → retired`

| Transição | Exige |
|---|---|
| `draft → testing` | JSON válido contra o schema da DSL; caminhos existentes no canônico (validação estática) |
| `testing → shadow` | todos os casos de teste passando |
| `shadow → published` | decisão manual; painel mostra taxa de disparo e amostras dos últimos N runs em sombra |
| `published → retired` | fecha `effective_until`; nova versão do mesmo `code` pode nascer em `draft` |

Publicar versão N+1 **não** retira a versão N: ambas coexistem e o motor escolhe pela vigência + maior versão publicada. Para "corrigir" a N (bug), publica-se N+1 com a mesma vigência.

**Pré-go-live (situação de hoje)**: as seeds de `db/seeds` são a fonte de verdade do catálogo e, em `development`/`test`, `seed_rule!` **sobrescreve** a definição publicada avisando em `stderr` (`seed_pre_golive_env?` em `00_helpers.rb`); em qualquer outro ambiente a divergência levanta exceção e exige versão nova. A licença existe porque não há base de produção: nenhum finding emitido depende das definições que ainda estão sendo acertadas (medido em 09/09/2026: zero findings no banco de dev para as regras cuja severidade mudou). **A partir do go-live**, toda mudança de `assert`, `severity`, `title` ou vigência nasce como versão N+1 — o caminho já exercitado por `IBSCBS.CBS.RATE_SCHEDULE` v1/v2.

Regra em `shadow` roda **junto** com a publicada de mesmo `code` (não a substitui): o `Rules::Resolver` devolve a maior versão `published` mais a maior `shadow`, e os findings da sombra nascem com `shadow: true` — invisíveis ao contador, visíveis na estatística de disparo. O resolver também acumula `warnings` (ex.: override de cliente com `replace`, que é privilégio da firma), que o run grava como `evaluation_error` de código `OVERRIDE`.

---

## 12. Validação estática (antes de rodar)

`Rules::Validator` (usado no painel ao salvar, na transição `draft → testing` e por `bin/rails rules:validate`) separa **erros** (bloqueiam) de **avisos** (informam):

1. Forma: `code` no padrão `PREFIX.SUBJECT.DETAIL`, `scope`/`severity` válidos, `message` e `effective_from` presentes, exatamente um de `assert` ou `primitive`, `dsl_version` = 1.
2. Todo `field`/`ref`/identificador de `calc` existe no dicionário do canônico (`Rules::CanonicalSchema`, escrito à mão a partir deste documento e do `CANONICO.md` — não há `canonical_schema.json` gerado). Raiz indisponível no escopo (ex.: `item.*` numa regra `period`) é **erro**; caminho de raiz conhecida que não consta do dicionário é **aviso** (o canônico evolui, e campo marcado [P] no `CANONICO.md` fica fora de propósito).
3. Toda `lookup.table` existe no Catalog e a aridade da `key` bate com `key_arity` da tabela.
4. `calc` compila; `approx` exige `tolerance` ou `tolerance_pct`; `between`/`length_between` exigem `[min, max]`; `{"param": x}` exige `x` declarado em `params`.
5. `message` e `group_by` só referenciam caminhos do canônico, variáveis de `let` ou `vars` da primitiva.
6. `primitive`: existe, o escopo bate com o da regra, não há param fora do `params_schema`, e a condição de `evidence` é validada no escopo `item`.

O que a validação estática **não** cobre: params obrigatórios sem default (a falta só aparece como `evaluation_error` na avaliação) e a existência da linha de tabela.

---

## 13. Exemplos completos

**Alíquota interestadual (item, lookup + approx)**

```jsonc
{
  "code": "ICMS.RATE.INTERSTATE", "version": 2, "scope": "item",
  "effective_from": "2013-01-01",
  "let": [{"lookup": "icms_interstate_rate",
           "key": [{"ref": "doc.operation.origin_uf"}, {"ref": "doc.operation.destination_uf"}, {"ref": "item.icms.origin_category"}],
           "as": "expected"}],
  "applies_when": {"all": [
    {"field": "doc.role", "op": "eq", "value": "issuer"},
    {"field": "doc.operation.scope", "op": "eq", "value": "interstate"},
    {"field": "scenario.tax_regime", "op": "in", "value": ["lucro_presumido", "lucro_real"]},
    {"field": "item.icms.taxation_kind", "op": "in", "value": ["taxed", "taxed_with_st", "reduced_base"]},
    {"field": "expected", "op": "present"}
  ]},
  "assert": {"field": "item.icms.rate", "op": "approx", "value": {"ref": "expected.rate"}, "tolerance": "0.001"},
  "severity": "error",
  "message": "Alíquota interestadual {{item.icms.rate}}% para {{doc.operation.origin_uf}}→{{doc.operation.destination_uf}} (origem {{item.icms.origin}}); esperado {{expected.rate}}%.",
  "group_by": ["doc.operation.destination_uf", "item.icms.rate", "expected.rate"]
}
```

**Grupo IBS/CBS obrigatório a partir de 2026 — duas vigências para o mesmo `code`**

A lei exige o grupo desde 01/01/2026, mas a SEFAZ só rejeita em produção a partir de 03/08/2026 (NT 2025.002 v1.40). Entre as duas datas a nota foi autorizada e está errada — caso típico do produto. Mesmo `code`, duas versões com vigências disjuntas:

```jsonc
{
  "code": "IBSCBS.GROUP.REQUIRED", "version": 1, "scope": "item",
  "effective_from": "2026-01-01", "effective_until": "2026-08-02",
  "applies_when": {"all": [
    {"field": "doc.role", "op": "eq", "value": "issuer"},
    {"field": "item.is_service", "op": "eq", "value": false}
  ]},
  "assert": {"field": "item.ibs_cbs.present", "op": "eq", "value": true},
  "severity": "error",
  "message": "Item sem grupo IBS/CBS. Obrigatório desde 01/01/2026 (NT 2025.002); a SEFAZ autorizou porque a rejeição só passou a valer em 03/08/2026.",
  "legal_references": [{"label": "LC 214/2025"}, {"label": "NT 2025.002 v1.40"}]
}
```

```jsonc
{
  "code": "IBSCBS.GROUP.REQUIRED", "version": 2, "scope": "item",
  "effective_from": "2026-08-03", "effective_until": null,
  "applies_when": { "...igual..." : null },
  "assert": {"field": "item.ibs_cbs.present", "op": "eq", "value": true},
  "severity": "error",
  "message": "Item sem grupo IBS/CBS em documento autorizado após 03/08/2026 — verifique se o XML está íntegro (a SEFAZ deveria ter rejeitado).",
  "legal_references": [{"label": "NT 2025.002 v1.40"}]
}
```

**Alíquota CBS do ano (item, lookup em cronograma — muda só o dado a cada ano)**

```jsonc
{
  "code": "IBSCBS.CBS.RATE_SCHEDULE", "version": 1, "scope": "item",
  "effective_from": "2026-01-01",
  "applies_when": {"all": [
    {"field": "item.ibs_cbs.present", "op": "eq", "value": true},
    {"field": "item.ibs_cbs.cst", "op": "eq", "value": "000"},
    {"field": "item.ibs_cbs.cbs.reduction_pct", "op": "absent"}
  ]},
  "assert": {"field": "item.ibs_cbs.cbs.rate", "op": "approx", "value": {"ref": "item.ibs_cbs.schedule_rates.cbs"}, "tolerance": "0.001"},
  "severity": "error",
  "message": "Alíquota CBS {{item.ibs_cbs.cbs.rate}}% diverge do cronograma vigente ({{item.ibs_cbs.schedule_rates.cbs}}%)."
}
```

**Cenário contradito pelas notas (scenario, primitiva)**

```jsonc
{
  "code": "SCENARIO.ST.DISAGREEMENT", "version": 1, "scope": "scenario",
  "primitive": {"name": "scenario_field_disagreement", "params": {
    "field": "st.applies",                   // caminho dentro do cenário, sem o prefixo `scenario.`
    "when_field_is": false,                  // só desconfia quando o cenário afirma "não opero com ST"
    "evidence": {"any": [{"field": "item.icms_st.highlights_st", "op": "eq", "value": true},
                         {"field": "item.icms.situation_code", "op": "in", "value": ["60", "500", "10", "30", "70", "201", "202", "203"]}]},
    "threshold": "0.20"
  }},
  "severity": "warning",
  "message": "{{share_pct}}% dos itens ({{matching_items}} de {{total_items}}) têm ST destacada ou retida, mas o cenário indica que o cliente não opera com ST. Revise o cenário."
}
```

**Duplicidade (cross_document, primitiva)**

```jsonc
{
  "code": "DOC.DUPLICATE.NUMBER_SERIES", "version": 1, "scope": "cross_document",
  "primitive": {"name": "duplicate_document", "params": {"match_on": "number_series_cnpj", "only_authorized": true}},
  "severity": "error",
  "message": "NF-e {{issuance.number}}/{{issuance.series}} autorizada duas vezes com chaves diferentes ({{access_keys}})."
}
```
