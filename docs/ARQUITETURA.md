# Decisões de arquitetura — Validador Fiscal

> Rascunho para discussão. Cada seção termina com **Decisão** (o que propomos seguir) e, quando houver, **Aberto** (o que depende de resposta do Igor).

---

## 0. Princípios que governam tudo

1. **Lei é dado, motor é código.** O código nunca sabe o valor de uma alíquota, um CST esperado ou uma data de corte. Ele sabe *avaliar* regras e *selecionar* a versão certa.
2. **Tempo é dimensão de primeira classe.** Toda regra, tabela e cenário tem `effective_from`/`effective_until`. A data de referência é sempre a **data do fato gerador** (`dhEmi` da nota; período de apuração do SPED), nunca "hoje".
3. **Nada publicado é editado.** Regras e tabelas publicadas são imutáveis; mudança = nova versão. Apontamento aponta para a versão exata que o gerou → auditabilidade completa.
4. **Todo apontamento é explicável.** Guarda evidência (valor encontrado × esperado, caminho no XML, item), regra+versão, referência legal e texto para contador.
5. **Reprocessável e idempotente.** Nota identificada por chave de acesso; auditoria é uma *execução* (run) — reprocessar um período gera novo run, sem destruir histórico.
6. **Código em inglês; termos legais em português.** Módulos, tabelas, colunas, campos do canônico, enums, códigos de regra e operadores da DSL são em inglês. Ficam em português apenas o que a legislação já padronizou: siglas (CST, CSOSN, CFOP, NCM, CEST, CRT, DIFAL, FCP, ICMS, IPI, PIS, COFINS, IBS, CBS, IS), regimes (`simples_nacional`, `lucro_presumido`, `lucro_real`), campos oficiais de XML/SPED/SINTEGRA. Prosa e mensagens ao contador em pt-BR.

---

## 1. Estrutura do sistema (monólito modular)

Rails API-only, um repositório, um deploy. Domínios isolados por namespace (opcionalmente Packwerk depois):

| Domínio | Responsabilidade | Depende de |
|---|---|---|
| `Accounts` | escritórios, usuários, clientes (CNPJs), billing por CNPJ | — |
| `Catalog` | tabelas de referência versionadas (NCM, CFOP, CEST, CST, alíquotas UF, cronograma IBS/CBS) + importadores | — |
| `Scenario` | cenário tributário do cliente, versionado com vigência | Catalog |
| `Ingestion` | upload, storage, parsers (NF-e, NFC-e, eventos, SPED, SINTEGRA) → **modelo canônico** | — |
| `Rules` | DSL, motor de avaliação, versionamento, casos de teste, publicação | Catalog |
| `Audit` | orquestra: documentos + cenário + regras vigentes → apontamentos; runs; triagem (falso positivo/justificado) | Ingestion, Scenario, Rules |
| `CrossCheck` | conciliação SPED/SINTEGRA × XML (fase 2) | Ingestion, Rules |
| `Simulation` | projeção IBS/CBS sobre mix real (fase 3) | Ingestion, Catalog, Scenario |
| `Reports` | PDF/exports com marca do escritório | Audit, Simulation |

**Decisão:** monólito modular; não microserviços. O que justifica separar processo é só o worker (Sidekiq), não o domínio.

---

## 2. Modelo canônico do documento (a peça mais subestimada)

Parsers **não** alimentam o motor com XML. Eles produzem um **documento canônico**: estrutura estável, tipada, desacoplada do layout da NF-e.

Por quê: o layout da NF-e muda (4.00 → grupos IBS/CBS/IS da NT 2025.002), NFC-e é diferente de NF-e, SINTEGRA/SPED representam a mesma nota de outro jeito. As regras precisam de **um** vocabulário: `item.icms.cst`, `item.icms.rate`, `doc.recipient.uf`, `doc.operation.nature` etc.

Regras de modelagem:

- **Campos derivados calculados na normalização, não na regra.** Ex.: `doc.operation.scope` (intrastate/interstate/foreign — a partir de `idDest`), `doc.operation.nature` (sale/sale_return/transfer/bonus/shipment… derivada de CFOP + finNFe), `item.icms.situation_field` (cst vs csosn), `doc.operation.final_consumer`, `doc.recipient.icms_taxpayer` (indIEDest). Assim as regras ficam curtas e legíveis.
- **Decimais como `BigDecimal`**, nunca float. Tolerâncias de arredondamento são parâmetro de regra (ex.: 0,01 por item, 0,05 por documento), não constante.
- **Versionar o próprio canônico** (`schema_version`). Quando um campo novo entra (ex.: `item.ibs_cbs.cst`, `item.ibs_cbs.class_code`), o documento antigo simplesmente não o tem e as regras usam `present`.
- **Persistência dupla:** XML bruto no S3 (imutável, prova); canônico em JSONB (`documents.data`) + colunas relacionais só para o que se filtra/agrupa (chave, cnpj_emitente, cnpj_destinatario, dhEmi, modelo, serie, numero, tipo_operacao, status, valor_total). `document_items` relacional com NCM, CFOP, CST, valores — porque cross-check e simulação agregam por eles.
- **Eventos são documentos.** Cancelamento, carta de correção, manifestação. Nota cancelada tem `status.state = cancelled` e não gera apontamentos tributários (mas gera no cross-check se estiver no SPED como normal).
- **Emitidas × recebidas.** Guardar `role` (issuer/recipient) em relação ao CNPJ monitorado. Regras de "meu cliente emitiu errado" só rodam em `issuer`; regras de entrada (crédito indevido, CFOP de entrada) rodam em `recipient`.

**Decisão:** modelo canônico documentado em `docs/CANONICO.md` (próximo passo), com o dicionário completo de campos antes de escrever qualquer regra.

---

## 3. Formato das regras — a decisão mais importante

Três opções avaliadas:

| Opção | Prós | Contras |
|---|---|---|
| A. JSON puro (JsonLogic-like) | 100% dado, editável em painel, seguro | vira "Turing tarpit" para regras cross-documento (duplicidade, devolução × original, sequência de numeração) |
| B. Ruby sandboxed no banco | expressivo | segurança, teste, e na prática deixa de ser "dado" |
| C. **Híbrido: DSL declarativa + validadores nativos registrados** | 90% das regras em JSON; as 10% complexas são "primitivas" em código, parametrizadas por dado | precisa disciplina para não vazar regra fiscal para o código |

**Decisão: C.** A distinção rígida é:

- **Primitiva (código):** sabe *como* comparar. Ex.: `items_sum_matches_totals`, `duplicate_document`, `return_references_original`, `table_lookup`, `numbering_gap`. Não sabe *nenhum* valor fiscal.
- **Regra (dado):** sabe *o que* é certo e *quando*. Ex.: "CSOSN esperado para devolução de venda no Simples é 900".

### 3.1 Anatomia de uma regra

```jsonc
{
  "code": "ICMS.CSOSN.SALE_RETURN",                // estável entre versões
  "version": 3,
  "effective_from": "2024-01-01", "effective_until": null,
  "scope": "item",                                 // item | document | cross_document | period | scenario
  "applies_when": {                                // filtro — quem a regra alcança
    "all": [
      {"field": "doc.role", "op": "eq", "value": "issuer"},
      {"field": "scenario.tax_regime", "op": "eq", "value": "simples_nacional"},
      {"field": "doc.operation.nature", "op": "eq", "value": "sale_return"}
    ]
  },
  "assert": {                                      // o que tem que ser verdade
    "field": "item.icms.csosn", "op": "eq", "value": "900"
  },
  "severity": "error",                             // error | warning | info
  "message": "Devolução de venda no Simples deve usar CSOSN 900; encontrado {{item.icms.csosn}}.",
  "explanation": "...texto para contador...",
  "legal_references": ["RICMS/xx art. ...", "Ajuste SINIEF 07/05 Anexo ..."],
  "params": {"tolerance": "0.01"},                 // usado por primitivas
  "primitive": null,                               // ou "duplicate_document", quando scope cross_document
  "tags": ["icms", "simples_nacional", "sale_return"]
}
```

Operadores da DSL (fechados, versionados junto com o motor): `eq, neq, in, not_in, gt, gte, lt, lte, between, present, absent, regex, lookup(table, key), calc(expr aritmética simples)`. Lookup é como a regra consulta tabela de referência **vigente na data do documento** (ex.: alíquota interna de SP para NCM X).

### 3.2 Escopos e o que o motor precisa suportar

| Escopo | Exemplo | Como o motor roda |
|---|---|---|
| `item` | CST × regime, alíquota × UF | por item, contexto = item + doc + scenario |
| `document` | soma itens = total; CFOP 5xxx com idDest=2 | por doc |
| `cross_document` | duplicidade, devolução > original, lacuna de numeração | primitiva recebe o conjunto do período/cliente |
| `period` | cross-check SPED × XML | primitiva recebe arquivo + documentos |
| `scenario` | cenário diz "sem ST" mas 30% das notas destacam ST → cenário provavelmente errado | primitiva estatística |

O escopo `scenario` é o diferencial "gaps que o cliente não sabe": o motor não só valida nota contra cenário, mas **desconfia do cenário** com base nas notas.

### 3.3 Ciclo de vida da regra

`draft → testing → shadow → published → retired`

- **Casos de teste obrigatórios** para publicar: cada regra tem N fixtures (XML ou canônico) com resultado esperado. Rodam automaticamente na publicação e no CI.
- **Modo sombra**: regra roda em produção mas apontamentos ficam invisíveis ao contador; admin vê taxa de disparo antes de liberar. Evita enxurrada de falso positivo.
- **Retirar** = fechar `effective_until`; documentos antigos continuam sendo avaliados por ela.

### 3.4 Resolução temporal (bitemporal simplificado)

Duas datas distintas, não confundir:

- **Vigência legal** (`effective_from/until`): quando a lei vale. Selecionada pela `dhEmi`.
- **Versão da regra** (`version`, `published_at`): quando *nós* mudamos nosso entendimento. Uma correção de bug na regra gera versão nova com a mesma vigência.

Seleção: para um documento de data D, pegar, por `code`, a **maior versão publicada** cuja vigência contém D. Apontamento (finding) grava `rule_version_id`. Reprocessar período depois de corrigir regra = novo run; run antigo fica como histórico ("o que o contador viu na época").

---

## 4. Cenário tributário do cliente

É o "gabarito". Se ele estiver pobre, o motor só valida estrutura — que é o que já existe no mercado.

Campos mínimos (v1):

- Regime: `simples_nacional | lucro_presumido | lucro_real`; sub-regime (Simples: anexo/faixa se quisermos validar PIS/COFINS; MEI fora?)
- UF, município, IE, contribuinte de IPI (industrial/equiparado), contribuinte ICMS
- CNAE principal e secundários → atividade (comércio/indústria/serviço/misto)
- Regimes especiais e benefícios: lista `{kind, legal_basis, effective_from/until, applies_to: NCM/CFOP}` — ex.: redução de base, crédito presumido, diferimento
- ST: **por padrão inferido da tabela CEST/NCM × UF** (Catalogo), com overrides por cliente ("este NCM aqui é ST por regime especial")
- Perfil de operação: vende para consumidor final? contribuinte? interestadual? exporta? usa NFC-e?
- **Vigência**: cliente muda de regime em janeiro → nova versão do cenário. Nota de dezembro valida com a anterior.

Overrides por produto: sem catálogo de produtos do cliente, o sistema infere por NCM. Permitir exceção `(cliente, NCM|cProd) → tratamento`.

**Decisão:** cenário em JSONB versionado (`tax_scenarios` com `effective_from/until`), com um *wizard* curto no MVP. Motor recebe o cenário **já resolvido** para a data da nota (`ResolvedScenario` = cenário + lookups do catálogo materializados).

**Aberto:** quanto do cenário o contador preenche à mão × quanto o sistema infere das primeiras notas e pede confirmação ("detectei que 95% das saídas usam CSOSN 102 — confirma Simples sem ST?"). Inferência assistida reduz drasticamente o atrito de onboarding.

---

## 5. Catálogo (tabelas de referência)

Modelo genérico:

```
reference_tables    (code: "ncm" | "cfop" | "cest" | "st_uf" | "icms_internal_rate" | "icms_interstate_rate" | "ibs_cbs_schedule" | "cst_icms" | "csosn" | "cst_pis_cofins" | "ibs_cbs_class" | "sped_layout" | "sintegra_layout" ...)
reference_versions  (table_id, version, effective_from, effective_until, source, imported_at, published)
reference_rows      (version_id, key (text[]), data JSONB)   -- índice GIN/btree na chave
```

- Importador por tabela (CSV/XLSX/JSON oficial). Versão só vale depois de `published`.
- Lookup do motor: `lookup("icms_internal_rate", [uf, ncm], date)` → resolve versão vigente → linha. Cache em memória por (tabela, versão).
- Fontes iniciais: NCM/TIPI (Siscomex/RFB), CFOP (Ajuste SINIEF), CEST (Convênio ICMS 142/18), alíquotas internas por UF (manual/curadoria — é o mais trabalhoso), cronograma IBS/CBS (LC 214/2025), tabela `cClassTrib` (NT 2025.002).

**Decisão:** tabelas genéricas em JSONB em vez de uma tabela relacional por tipo. Custa um pouco de tipagem, ganha em "adicionar tabela nova sem migração".

---

## 6. Parsers versionados por layout

- **NF-e/NFC-e:** Nokogiri; mapeamento XML→canônico por `versao_layout` (4.00 hoje; grupos IBS/CBS/IS quando presentes). Um mapper por layout, canônico único.
- **SPED EFD ICMS/IPI:** leiaute muda **anualmente**. Em vez de um parser por ano em código, a **especificação do leiaute é dado**: `{record_type: "C170", layout_version: "019", fields: [{name, position, type, required}]}`. Parser genérico lê a spec vigente na data do período do arquivo. Mesma ideia para SINTEGRA (Convênio 57/95, mais estável).
- Validações **estruturais** do arquivo (campo obrigatório, tipo) viram apontamentos também, com regra `SPED.STRUCTURE.*`.

**Decisão:** spec de leiaute SPED/SINTEGRA em dado (tabela do Catálogo), parser genérico.

---

## 7. Pipeline de processamento

```
upload (ZIP/XML/TXT) ──► S3 ──► ExtractBatchJob
   ──► ParseDocumentJob (por arquivo, idempotente por access_key/hash)
        ──► canonical document persistido (documents + document_items)
   ──► AuditDocumentJob (scopes item/document)                 ─┐
   ──► AuditPeriodJob  (scopes cross_document, scenario, period)─┴─► AuditRun → Findings
```

- `upload_batches` com status e contagem; erros de parse viram apontamento de severidade `bloqueante` no lote, não exception silenciosa.
- **AuditRun** = (client, period, snapshot das versões de regras/tabelas/cenário usados). Reprocessar = novo run. UI mostra o último run; histórico acessível.
- Sidekiq com filas `ingestion`, `audit`, `reports`; jobs idempotentes (chave de acesso + hash do XML).
- Volume esperado: milhares de notas/cliente/mês × dezenas de clientes/escritório — Postgres aguenta anos disso; particionar `document_items` por mês só se necessário.

---

## 8. Triagem e feedback (o que evita churn)

Apontamento (`finding`) tem estado: `open → justified | false_positive | fixed | ignored`. Justificativa do contador é guardada e **suprime recorrência** (mesma regra + mesmo padrão + mesmo cliente) até o cenário mudar. Falsos positivos marcados alimentam a curadoria de regras (painel admin: regras com maior taxa de FP).

---

## 9. Multi-tenancy, segurança e LGPD

- Row-level: `firm_id` em tudo, scoping obrigatório via `current_firm` (default scope explícito, não mágico). RLS do Postgres como segunda camada quando maduro.
- XML em S3 com SSE, bucket privado, URL assinada. Retenção configurável por escritório (ex.: 5 anos = prazo decadencial) e exclusão a pedido.
- Log de acesso a documentos (quem baixou o quê).
- Certificado A1 (fase 4): nunca armazenar sem criptografia com chave fora do banco (KMS/Vault).

---

## 10. Stack (confirmando e ajustando)

| Camada | Escolha | Nota |
|---|---|---|
| Backend | **Rails 8** API-only | mesma curva que Rails 7, ganha Solid Queue/Cache nativos |
| Jobs | **Sidekiq** (Redis) | ou Solid Queue se quiser zero Redis; Sidekiq tem melhor observabilidade |
| Banco | PostgreSQL 16+ | JSONB, GIN, `numeric` |
| Storage | S3-compatível (Cloudflare R2 / Backblaze — sem egress) | Active Storage |
| XML | Nokogiri | SAX só se aparecer XML gigante (NF-e é pequena) |
| Frontend | Vue 3 + Tailwind + Pinia | painel do contador e painel admin de regras no **mesmo** app, rotas/roles diferentes |
| Auth | Devise + JWT ou Rodauth | 2FA desde o início (dado fiscal de terceiros) |
| Testes | RSpec + fixtures de XML reais anonimizados | fixtures são também os casos de teste das regras |
| Infra | Fly.io ou Hetzner + Kamal | Kamal é o caminho natural em Rails 8 |

---

## 11. Regras de negócio candidatas ao MVP (~20)

Agrupadas por escopo. Todas são *dado*; a lista é para dimensionar as primitivas e o canônico.

**Coerência com regime**
1. Emitente Simples → todo item usa CSOSN (não CST ICMS); regime normal → CST. (`ICMS.REGIME.SITUATION_FIELD`)
2. PIS/COFINS CST × regime: Simples → CST 49 saída/ 99; Presumido → 01 (0,65/3,00); Real → 01 (1,65/7,60) salvo NCM monofásico/alíquota zero (lookup).
3. IPI destacado por não-contribuinte de IPI (comércio puro) — alerta.
4. Simples destacando ICMS próprio com alíquota (CSOSN 101 tem crédito, mas não destaque cheio) — erro.

**Operação × CFOP**
5. CFOP 5xxx com `idDest=2` ou 6xxx com `idDest=1` — erro.
6. CFOP 7xxx sem exportação (`idDest=3` / UF EX) — erro.
7. NFC-e com CFOP 6xxx/7xxx ou destinatário contribuinte — erro.
8. `finNFe=4` (devolução) sem `refNFe`; ou CFOP de devolução com `finNFe=1` — erro.
9. Devolução referenciando nota que não existe na base ou de outro CNPJ; quantidade/valor devolvido > original (acumulado) — erro/alerta (`cross_document`).
10. CFOP de devolução de venda com CSOSN/CST diferente do esperado (ex.: Simples → 900; normal → espelhar CST da original).

**ICMS**
11. Alíquota interestadual: 4% (origem 1,2,3,8), 7% ou 12% conforme UF origem→destino — lookup `aliq_interestadual`.
12. Alíquota interna divergente da tabela UF × NCM vigente — lookup (começa com alíquota geral da UF; NCM específico conforme curadoria).
13. CST 60 / CSOSN 500 (ST retido) em NCM/CEST **não** sujeito a ST na UF — alerta; inverso (NCM com ST e CST 00/102) — erro.
14. CEST ausente em item com NCM sujeito a ST — erro.
15. DIFAL: venda interestadual a não-contribuinte (`indIEDest=9`) sem grupo `ICMSUFDest` — erro (regime normal); Simples — alerta informativo conforme entendimento vigente (regra com vigência!).
16. Base de cálculo ≠ `vProd - vDesc + vFrete + vSeg + vOutro` (± tolerância) sem redução declarada (`pRedBC`) — erro.
17. `vICMS ≠ vBC × pICMS` (± tolerância) — erro.

**Integridade do documento**
18. Soma dos itens ≠ totais (`vProd`, `vBC`, `vICMS`, `vNF`) — erro.
19. NCM inexistente na tabela vigente na data de emissão — erro; NCM de 2 dígitos genérico ("00000000") em item que não é serviço — alerta.
20. Duplicidade: mesma chave duas vezes (ignorar); mesmo `nNF+serie+CNPJ` com chaves diferentes e ambas autorizadas — erro (`cross_document`).
21. Lacuna de numeração sem inutilização/cancelamento correspondente — alerta (`cross_document`).
22. Nota cancelada (evento) com apontamentos tributários → suprimir; cancelada com movimento no SPED → cross-check.

**Reforma tributária (vigência ≥ 2026-01-01)**
23. Documento emitido ≥ 01/2026 sem grupos IBS/CBS (`IBSCBS`) — erro (obrigatoriedade NT 2025.002).
24. `CST IBS/CBS` × `cClassTrib` incoerentes (lookup tabela cClassTrib vigente) — erro.
25. Alíquotas IBS/CBS fora do cronograma do ano (2026: CBS 0,9% / IBS 0,1% teste; 2027+: conforme tabela) — erro. **Exemplo canônico de regra que muda todo ano só trocando dado.**
26. Operação em que a base IBS/CBS não bate com a base esperada (por enquanto = mesma do produto; refinar).

**Cenário (desconfiar do gabarito)**
27. Cenário sem ST mas > X% dos itens com ST destacada (ou vice-versa) — alerta "revise o cenário".
28. Cenário Simples mas notas com CST — provável regime desatualizado.

---

## 12. Decisões fechadas (29/08/2026)

| # | Tema | Decisão |
|---|---|---|
| 1 | Documentos | **Emitidas e recebidas.** Canônico carrega `doc.role` (issuer/recipient) em relação ao CNPJ monitorado. Recebidas entram no cross-check SPED/SINTEGRA e em regras de entrada (crédito, CFOP de entrada, manifestação). |
| 2 | Tributos no MVP | **Todos**: ICMS/ST, DIFAL, IPI, PIS/COFINS, IBS/CBS/IS. O canônico nasce completo; as regras entram por prioridade. |
| 3 | Curadoria de regras | Só o Igor no início, mas **arquitetura multi-camada desde o dia 1** (ver 13). |
| 4 | Alíquotas/ST | Base padrão curada + atualização periódica; **sobreponível por escritório/cliente** (ver 13). |
| 5 | Fora de escopo | NFS-e/ISS, CT-e, MDF-e. |
| 10 | UFs prioritárias | **Sudeste (SP, MG, RJ, ES)** para curadoria de ST e alíquotas por produto; demais UFs só alíquota geral + FCP. |
| 11 | Certificado SVRS | e-CNPJ A1 próprio da plataforma para a API de tabelas IBS/CBS; armazenado em KMS/Vault. |
| 9 | Idioma | **Código em inglês**; só termos padronizados pela legislação em português (princípio 6). |
| 6 | Stack | **Rails 8** API-only + **Sidekiq**. Jobs usam só API do ActiveJob (sem `Sidekiq::Worker` direto) para manter a troca de adapter possível. |
| 7 | Onboarding | **Inferência assistida**: sistema propõe cenário a partir das notas, contador confirma. |
| 8 | Painel admin de regras | **No MVP.** Regras vivem no banco desde o início; o repositório carrega apenas um seed inicial. |

---

## 13. Camadas de sobreposição (regras e tabelas)

Consequência das decisões 3 e 4: contadores discordam entre si, e clientes têm regimes especiais. Regras e tabelas passam a ter **escopo de origem** e o motor resolve por precedência:

```
client  >  firm  >  platform (base)
```

### 13.1 Modelo

- `rules` e `reference_rows` ganham `source_type` (`platform | firm | client`) e `source_id`.
- Uma sobreposição referencia o `code` da regra base (ou a chave da linha de tabela) e diz o que muda: `disable`, `severity`, `expected value`, `params`, ou regra inteiramente nova (`codigo` próprio com prefixo do escritório).
- Sobreposições **também têm vigência** (a isenção do cliente vale de/até).
- Resolução na montagem do run: `ResolvedRules(client, date)` = base vigente ⊕ overrides do escritório ⊕ overrides do cliente. O run grava a lista resolvida (snapshot) → auditabilidade.

### 13.2 Responsabilidade

Todo apontamento carrega `rule_source` (platform/firm/client). No relatório: "conforme regra da plataforma" × "conforme parametrização do escritório (usuário X, em DD/MM)". Isso é o que transfere a responsabilidade ao contador quando ele sobrescreve. Registrar sempre: quem, quando, justificativa (campo obrigatório ao sobrescrever regra base).

### 13.3 O que o contador pode editar (fases)

- **MVP:** tabelas por cliente (alíquota interna específica, isenção/redução de base por NCM, ST por regime especial) e **desativar/rebaixar severidade** de regra base com justificativa. Sem criar regra nova.
- **Depois:** criar regra própria no painel (mesma DSL, mesmo fluxo draft → testing → shadow → published, limitado ao escopo do escritório).

Isso obriga a DSL a ser **segura por construção** (operadores fechados, sem código) já agora — reforça a opção C da seção 3.

### 13.4 Atualização periódica da base

- Cada tabela base tem `source` (URL/documento legal) e `next_review_at`. Painel admin lista tabelas vencidas.
- Importar versão nova **não apaga** sobreposições de escritório/cliente; elas continuam válidas dentro da própria vigência. Painel avisa quando uma sobreposição conflita com a nova base ("sua alíquota para NCM X em SP difere da base vigente desde 01/07").
- Automatizar a coleta (scraping/consulta de fontes oficiais) fica para depois; primeiro o processo manual com versionamento.

---

## 14. Inferência assistida do cenário

Rodada de análise sobre o primeiro lote de notas de um cliente (ou a qualquer momento por demanda):

- Distribuições: CST × CSOSN (→ regime), CFOPs (→ atividade, âmbito, uso de NFC-e), `indIEDest` (→ perfil de destinatário), ST destacada por NCM (→ ST aplicável), IPI destacado (→ contribuinte IPI), PIS/COFINS CST (→ regime confirma), presença de grupos IBS/CBS.
- Saída: **proposta de cenário** com nível de confiança por campo e a evidência ("97% dos itens com CSOSN → Simples Nacional"). Contador confirma/ajusta campo a campo; o cenário publicado guarda `origin: inferred|manual` por campo.
- Reutiliza o mesmo mecanismo do escopo `scenario` das regras (seção 3.2): as primitivas estatísticas servem tanto para propor quanto para desconfiar.

---

## 15. Próximos passos

1. ✅ `docs/CANONICO.md`, `docs/DSL_RULES.md`, `docs/DATA_SOURCES.md`.
2. ✅ Esqueleto (29/08/2026): monorepo `api/` (Rails 8.1, Sidekiq 8, PG 17) + `web/` (Vue 3, Vite, Tailwind 4, Pinia) + `docker-compose.yml`. Migration do núcleo, models por domínio, DSL completa (`Rules::Dsl::*`), `Rules::Engine`/`Resolver`, primitivas `items_sum_matches_totals` e `duplicate_document`, parser NF-e + derivações, importador idempotente, jobs, `Audit::Runner`, API mínima e painel de findings. Seeds com 7 tabelas do Catalog e 13 regras. Fluxo ponta a ponta verificado (RSpec 10/10 e via HTTP).
3. ✅ Fechamento do MVP (30/08/2026), itens 1–4:
   - **Auth/multi-tenant**: JWT de acesso (15 min) + refresh token opaco com rotação por família (reuso revoga a família), TOTP com códigos de backup, bloqueio após 5 falhas, Rack::Attack, `audit_logs`; papéis `platform_admin | firm_admin | accountant`; tudo escopado por `firm_id` (`X-Client-Id` só seleciona cliente da própria firma).
   - **Clientes e cenário**: CRUD de clientes; cenários versionados com `draft → published` (publicar fecha o anterior); `Scenario::Validator` server-side; `Scenario::Inference` (proposta com confiança e evidência por campo); formulário extenso com vee-validate + zod (`web/src/schemas/taxScenario.js`).
   - **Painel admin**: `Rules::Validator` (estático, DSL_RULES §12, com dicionário canônico em `Rules::CanonicalSchema`), `Rules::TestRunner` (casos de teste com stub de catálogo), transições `draft → testing → shadow → published → retired` com exigências, estatísticas de disparo em sombra; tabelas/versões com import CSV/JSON (replace/merge), diff contra versão anterior, publicação que fecha a anterior; sobreposições de regra (`override_action`: disable/enable/adjust/replace) e de linha de tabela por firma/cliente com justificativa obrigatória.
   - **Regras e catálogo**: 30 regras seed; primitivas `numbering_gap`, `return_references_original`, `scenario_field_disagreement` (+ `Audit::Stats` para o escopo `scenario`); `Ingestion::ReferenceResolver` (referências resolvidas nos dois sentidos); eventos/inutilizações entram no período; importadores classe A `Catalog::Importers::Ncm` (Siscomex JSON público) e `IbsCbsClass` (SVRS API com certificado via `SVRS_CERT_P12`/`SVRS_CERT_PASSWORD`, ou upload do JSON) acionados por `POST /admin/reference_tables/:id/sync`.
4. ✅ Base de regras completa e revisada (30/08/2026, ver `docs/RULES_REVIEW.md`): **88 regras ativas** em `db/seeds/03..05`, todas com casos de teste (`06_rule_test_cases.rb`, 206 casos, `bin/rails rules:test` verde). Catálogo enriquecido: CFOP com `st_role` (substitute/substituted/none), `requires_reference`, `own_production`; tabela `cst_ipi`; direção do CST PIS/COFINS. Derivações novas: `icms_st.expected_base_amount` (MVA), `icms_st.expected_amount`, `icms_uf_dest.expected_destination_amount`, `expected_cest`, `st_applicable_by_catalog`, `cfop_st_role`. Primitivas novas: `numbering_order`, `event_consistency`. Tabelas registradas sem versão (`tipi`, `pis_cofins_special`, `ibs_cbs_class`, `cest`, `st_uf`, `ncm`): as regras que dependem delas viram `evaluation_error` até a importação — sinal para o admin.
5. ✅ (31/08/2026) Tabelas todas preenchidas (DATA_SOURCES §2b) com sync automático classe A (sidekiq-cron) e validação ponto a ponto (`docs/VALIDATION_2026-08-31.md`); ingestão do formato de exportação do ERP (zip aninhado autorização+cancelamento; eventos fora de ordem); 27 alíquotas internas gerais; **relatório de cobertura** (`Audit::Coverage` + `/admin/reference_tables/curation_queue`) puxando a curadoria de `st_uf`/alíquotas por NCM pela demanda real; **relatório PDF** com a marca do escritório (`Reports::AuditRunPdf`, `GET /audit_runs/:id/report.pdf`, botão no painel).
6. ✅ (31/08/2026) **Fase 2 — cross-check EFD ICMS/IPI × XML**: leiaute como dado (`sped_layout`, 17 registros do Guia Prático, parser genérico tolerante com decimais normalizados e detecção de encoding), `Audit::SpedContext` (C100 + filhos), 4 primitivas (`sped_document_reconciliation` presence/cancelled/values, `sped_item_reconciliation` com CST de 3 dígitos, `sped_c190_consistency`, `sped_structure`) e 6 regras `SPED.*` com 15 casos; findings apontam **registro (linha) e nota/item de origem** (`fiscal_record_id` no motor); upload da EFD na tela de envio com vínculo automático aos XMLs; o run escolhe o arquivo do período e grava `fiscal_file_id` no snapshot.
7. ✅ (31/08/2026) Validação SPED contra o Guia Prático v3.2.3: **leiaute 020 completo importado (263 registros, campos + níveis, `db/data/sped_layout_020.json`)**, hierarquia do parser por nível oficial, e correções materiais nas primitivas (IND_FRT no C100; NFC-e no C100 nas saídas; COD_SIT 02/03; fallback por série/número; regra nova `SPED.DOC.NO_ANALYTIC`; COD_SIT 08/Ajuste 49-25 fora da conferência de totais). Adendo completo em `RULES_REVIEW.md`. Cliente de teste do SPED: **Victor Dzenk** (IRMAOS DZENKAUSKAS, CNPJ 66412974000190, id 55, MG, confecção, não optante — cenário rascunho aguardando XMLs+EFD).
8. Próximos: testar com EFD real do Victor Dzenk; SINTEGRA (mesmo desenho); curadoria pela fila; fornecedor de conteúdo na escala.
