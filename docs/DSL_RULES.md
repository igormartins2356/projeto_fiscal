# DSL de regras — especificação

> Define o formato das regras (dado em JSONB), os operadores, o contexto disponível por escopo, as primitivas nativas, o cenário resolvido, os casos de teste e as sobreposições por firma/cliente. Complementa `ARQUITETURA.md` (seções 3 e 13) e usa o vocabulário de `CANONICO.md`.
>
> Versão da DSL: **`dsl_version: 1`**. O motor rejeita regras com versão desconhecida. Adicionar operador = minor; mudar semântica = major (regras antigas continuam avaliadas pela versão declarada).

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
  "group_by": ["item.icms.rate", "expected"],   // agrupamento no painel (seção 8)
  "dedupe_key": null                            // opcional; default = code + document + item
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
- **Coerção**: comparações `gt/lt/between` exigem os dois lados numéricos ou ambos data; caso contrário → `evaluation_error`. `eq` entre `decimal` e string numérica compara numericamente (`"18.00" == "18"`).
- **Literais**: qualquer JSON. Referência a outro campo: `{"ref": "item.icms.expected_amount"}`. Expressão: `{"calc": "..."}` (seção 4).
- **Ausência**: campo inexistente é `absent`. Só `present`, `absent`, `eq`/`neq` contra `null` e `in` com `null` na lista aceitam `absent`; outros operadores → `evaluation_error`.

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
- Funções: `round(x, n)` (`ROUND_HALF_UP`), `abs`, `min`, `max`, `sum(list.path)`, `coalesce(a, b)`, `year(date)`, `month(date)`, `days_between(a, b)`, `len(list)`.
- Identificadores = caminhos do contexto e variáveis de `let`/`params` (`params.tolerance`).
- Sem loops, sem strings mutáveis, sem acesso a nada fora do contexto. Parser próprio (não `eval`); AST cacheado por regra.

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

`period` = `{client, start_date, end_date, documents[], events[], invalidations[]}` — só documentos com `status.state != rejected`. Documentos `cancelled` ficam em `period.documents` com o status; regras de escopo `item`/`document` **não rodam** em cancelados/denegados (filtro do motor, não da regra).

`stats` (escopo `scenario`): `stats.distribution("item.icms.situation_code")` → `{"102": 0.93, "500": 0.07}`; `stats.share(where)` → fração de itens/docs que satisfazem a condição; `stats.count(where)`.

---

## 6. Primitivas nativas (v1)

Primitivas são classes Ruby registradas em `Rules::Primitives`, sem valor fiscal embutido; tudo que é "esperado" vem de `params` ou de `let`. Cada primitiva declara `scope`, `params_schema` e o formato do `finding` que emite.

| Nome | Escopo | Params | Emite finding por |
|---|---|---|---|
| `items_sum_matches_totals` | document | `fields[]` (ex.: `products, icms_base, icms`), `tolerance` | campo divergente |
| `duplicate_document` | cross_document | `match_on` (`access_key` \| `number_series_cnpj`), `only_authorized` | par duplicado |
| `numbering_gap` | cross_document | `max_gap_ignored`, `consider_invalidations` | intervalo faltante por série |
| `return_references_original` | cross_document | `require_resolved`, `compare` (`quantity` \| `amount` \| `both`), `tolerance`, `mirror_fields[]` (ex.: `icms.cst`) | devolução com problema |
| `references_exist` | cross_document | `kinds[]` | referência não resolvida |
| `event_consistency` | cross_document | — | nota com evento incoerente (cancelamento após prazo; CC-e em cancelada) |
| `scenario_field_disagreement` | scenario | `field` (caminho no cenário), `evidence` (condição sobre item/doc), `threshold` | cenário contradito pelas notas |
| `sped_document_reconciliation` | period | `direction` (`xml_to_file` \| `file_to_xml` \| `both`), `compare_fields[]`, `tolerance` | nota ausente/sobrando/divergente |
| `sped_item_reconciliation` | period | `compare_fields[]`, `tolerance` | item divergente (C170 × item) |
| `sped_structure` | period | `layout` | registro/campo inválido pela spec |
| `sintegra_reconciliation` | period | idem SPED, registros 50/54 | |

Adicionar primitiva é deploy; deve ser raro. Se uma regra "precisa" de primitiva nova, primeiro verificar se `let` + quantificadores resolvem.

---

## 7. Cenário resolvido (`scenario`)

O motor nunca lê `tax_scenarios` cru; recebe `ResolvedScenario.for(client, date)`:

```jsonc
{
  "tax_regime": "simples_nacional",          // simples_nacional | simples_nacional_excess | lucro_presumido | lucro_real | mei
  "simples_annex": "I",                      // opcional
  "uf": "SP", "city_code": "3550308",
  "icms_taxpayer": true, "ipi_taxpayer": false, "iss_taxpayer": false,
  "activity": ["commerce"],                  // commerce | industry | service | rural | mixed
  "cnae": {"primary": "4711302", "secondary": []},
  "sells_to_final_consumer": true, "uses_nfce": true, "exports": false, "imports": false,
  "st": {"source": "catalog", "overrides": [{"ncm": "2202*", "applies": false, "legal_basis": "...", "effective_from": "..."}]},
  "benefits": [{"kind": "reduced_base", "pct": "33.33", "applies_to": {"ncm": ["0402*"]}, "legal_basis": "...", "effective_from": "...", "effective_until": null}],
  "pis_cofins": {"regime": "simples"},       // simples | cumulative | non_cumulative
  "ibs_cbs": {"regime": "regular"},          // regular | simples_nacional_opt_in | ...
  "field_origins": {"tax_regime": "inferred", "ipi_taxpayer": "manual"},
  "version_id": 42, "effective_from": "2026-01-01"
}
```

Wildcards `*` em NCM/CFOP são aceitos onde a doc marcar. `scenario.benefits` e `scenario.st.overrides` são consultáveis com quantificadores (`some scenario.benefits where …`).

---

## 8. Findings

```jsonc
{
  "rule_code": "ICMS.RATE.INTERSTATE", "rule_version_id": 913, "rule_source": "platform",   // platform | firm | client
  "audit_run_id": 771, "document_id": 9981, "item_number": 3,
  "severity": "error", "scope": "item",
  "message": "…renderizada…",
  "evidence": {"item.icms.rate": "12.00", "expected": "7.00", "doc.operation.origin_uf": "SP", "doc.operation.destination_uf": "BA"},
  "xml_path": "/nfeProc/NFe/infNFe/det[3]/imposto/ICMS/ICMS00/pICMS",
  "group_key": "12.00|7.00",
  "dedupe_key": "ICMS.RATE.INTERSTATE|9981|3",
  "state": "open"                            // open | justified | false_positive | fixed | ignored
}
```

- `evidence` = todos os campos referenciados em `applies_when`/`assert`/`message` com seus valores; é o que dá auditabilidade.
- `xml_path` é derivado do mapeamento canônico → XML (o parser guarda o caminho de origem por campo). Permite abrir o XML no ponto exato.
- `group_key` agrupa no painel ("14 notas com alíquota 12% onde se esperava 7%").
- `dedupe_key` estável entre runs: permite carregar `state` do run anterior (uma justificativa não some ao reprocessar).

---

## 9. Sobreposições (firma / cliente)

Duas famílias, ambas com vigência e com autoria obrigatória (`created_by`, `justification`).

### 9.1 Sobre regra (`rule_overrides`)

```jsonc
{
  "rule_code": "ICMS.CSOSN.SALE_RETURN",
  "source_type": "client", "source_id": 118,
  "effective_from": "2026-01-01", "effective_until": null,
  "override_action": "adjust",              // disable | enable | adjust | replace
  "patch": {                                // só para adjust
    "severity": "warning",
    "params": {"tolerance": "0.05"},
    "assert": {"field": "item.icms.csosn", "op": "in", "value": ["900", "400"]}
  },
  "justification": "Cliente possui decisão administrativa nº … permitindo CSOSN 400.",
  "created_by": 7
}
```

- `disable`: regra não roda para o alvo.
- `adjust`: substitui campos listados (`severity`, `params`, `assert`, `applies_when`, `message`). O `code` e o `scope` nunca mudam.
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
  "rule_code": "ICMS.CSOSN.SALE_RETURN", "rule_version": 3,
  "name": "devolução de venda com CSOSN 102 no Simples",
  "reference_date": "2026-03-14",
  "scenario": {"tax_regime": "simples_nacional", "uf": "SP"},         // parcial; resto vem de um default
  "input": {"kind": "canonical", "document": { ...recorte canônico... }},   // ou {"kind": "xml", "fixture": "fixtures/nfe/sale_return_csosn_102.xml"}
  "catalog": {"icms_interstate_rate": [{"key": ["SP","BA","domestic"], "data": {"rate": "7.00"}}]},   // opcional, sobrepõe o catálogo real no teste
  "expect": {"findings": [{"item_number": 1, "severity": "error", "evidence": {"item.icms.csosn": "102"}}]}   // ou {"findings": []}
}
```

- Rodam na publicação (bloqueiam), no CI (todas as regras publicadas contra o motor atual) e sob demanda no painel.
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

---

## 12. Validação estática (antes de rodar)

O painel valida ao salvar:

1. Schema JSON da DSL (`dsl_version` correspondente).
2. Todo `field` existe no dicionário do canônico para o escopo (lista gerada a partir de `CANONICO.md` → `canonical_schema.json` mantido no repositório).
3. Toda `lookup.table` existe no Catalog e a aridade da `key` bate com a tabela.
4. `calc` compila; identificadores resolvem.
5. `message` só referencia variáveis disponíveis.
6. `primitive.params` valida contra o `params_schema` da primitiva.

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
    "field": "st.applies_any",
    "evidence": {"field": "item.icms_st.highlights_st", "op": "eq", "value": true},
    "threshold": "0.20"
  }},
  "severity": "warning",
  "message": "{{stats.share_pct}}% dos itens destacam ICMS-ST, mas o cenário indica que o cliente não opera com ST. Revise o cenário."
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
