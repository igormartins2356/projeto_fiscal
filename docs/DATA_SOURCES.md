# Fontes de dados — tabelas de referência e legislação

> Para cada tabela do Catalog: de onde vem, quem publica, formato, frequência de mudança, se dá para automatizar, e o que é curadoria manual. Levantado em 29/08/2026; URLs verificadas nessa data.
>
> Regra geral: **toda linha de tabela carrega `legal_basis` e `source_url`**. Sem base legal, a linha não é publicada.

---

## 0. Classificação das fontes

| Classe | Significado | Exemplo |
|---|---|---|
| **A — máquina** | Arquivo/API oficial, estruturado, estável. Importador automático + diff. | NCM (Siscomex JSON), cClassTrib (SVRS JSON/API) |
| **B — semi** | Oficial, mas PDF/HTML/XLS que muda de formato. Importador com parser frágil + revisão humana do diff. | CFOP, CEST, TIPI, leiaute EFD, tabelas SPED |
| **C — curadoria** | Não existe tabela oficial consolidada; a fonte é a lei de cada UF. Manual, com base legal por linha. | Alíquotas internas por UF, ST por UF, benefícios |
| **D — parâmetro** | Valor fixado por ato normativo, poucos registros, muda raramente. Manual. | Alíquotas interestaduais, cronograma IBS/CBS |

---

## 1. Tabelas do Catalog

### 1.1 `ncm` — Nomenclatura Comum do Mercosul — classe **A**

- **Fonte:** Portal Único Siscomex, API pública sem captcha: `https://portalunico.siscomex.gov.br/classif/api/publico/nomenclatura/download/json?perfil=PUBLICO`
- **Publica:** RFB/Siscomex (base: Resoluções GECEX/Camex; TEC)
- **Conteúdo:** código, descrição, `Data_Inicio`/`Data_Fim` por código (já vem com vigência!)
- **Frequência:** várias vezes ao ano (ajustes GECEX); grandes revisões a cada 5 anos (SH 2022, próxima SH 2027)
- **Automação:** job semanal → diff → nova versão em `draft` → publicação com um clique
- **Uso:** `item.ncm_valid`, `ncm_chapter`; base para CEST/ST/IPI

### 1.2 `tipi` — alíquotas de IPI por NCM — classe **B**

- **Fonte:** Decreto 11.158/2022 (TIPI consolidada) + ADEs RFB (último: ADE RFB nº 1/2026, efeitos 01/02/2026). Página oficial: gov.br/receitafederal → IPI → TIPI (PDF/XLS)
- **Frequência:** 1–3 vezes ao ano
- **Automação:** parser de XLS quando disponível; senão PDF → revisão manual do diff
- **Uso:** alíquota IPI esperada por NCM (regra `IPI.RATE.TIPI`), `ex_tipi`

### 1.3 `cfop` — classe **B**

- **Fonte:** Ajuste SINIEF s/nº de 1970, Anexo (CONFAZ): `https://www.confaz.fazenda.gov.br/legislacao/ajustes/sinief/cfop_cvsn_70_vigente`; cópia no Portal SPED (`sped.rfb.gov.br/arquivo/show/85`) e no Portal NF-e (Documentos → Diversos)
- **Alterações recentes:** Ajuste SINIEF 03/22, 29/23, 03/24 (vigência jun/2024)
- **Frequência:** ~1 vez ao ano
- **Automação:** parser HTML da página CONFAZ; revisão manual
- **Curadoria nossa (colunas extras, versionadas junto):** `nature` (sale, sale_return, transfer…), `direction`, `scope`, `st_related` (bool), `requires_reference` (bool) — não existem oficialmente; são a base de `operation.nature`

### 1.4 `cest` — Código Especificador da ST — classe **B**

- **Fonte:** Convênio ICMS 142/2018, Anexos II a XXVI (CONFAZ): `https://www.confaz.fazenda.gov.br/legislacao/convenios/2018/CV142_18`
- **Conteúdo:** CEST × NCM(s) × descrição × segmento
- **Frequência:** alterações por convênios (ex.: Conv. 206/23); algumas por ano
- **Automação:** parser HTML/PDF dos anexos; diff manual
- **Uso:** `item.expected_cest`; pré-requisito da tabela `st_uf`

### 1.5 `st_uf` — NCM/CEST sujeitos a ST **por UF** — classe **C** (a mais cara)

- **Por que C:** o Conv. 142/18 lista o que *pode* ter ST; cada UF decide o que *tem*, via adesão a Protocolos/Convênios ICMS e seu RICMS. Não há tabela nacional consolidada.
- **Fontes por linha:** RICMS da UF (anexo de ST) + Protocolos ICMS (CONFAZ, `/legislacao/protocolos`) + Convênios de adesão
- **Modelo:** `key = [uf, cest]` → `{applies: bool, mva_original_pct, mva_adjusted_pct?, legal_basis, protocol_ref}`; MVA é opcional no MVP (regras de "tem ST ou não" já pegam a maior parte dos erros)
- **Estratégia:** começar pelo **Sudeste (SP, MG, RJ, ES)**; **inferência cruzada** — quando muitas notas de vários clientes destacam ST para um CEST numa UF e a tabela diz "não", o painel admin recebe um alerta de curadoria ("suspeita de linha desatualizada")
- **Ajuda externa:** fornecedores de conteúdo fiscal vendem essa tabela pronta (Systax, Mix Fiscal, IOB…). Vale avaliar assinatura na fase 2 em vez de curar 27 UFs à mão.

### 1.6 `icms_internal_rate` — alíquotas internas por UF (geral e por NCM/CEST) — classe **C**

- **Por que C:** não existe fonte oficial consolidada; blogs (Focus, NS, Simtax) compilam mas não são fonte
- **Fontes por linha:** lei estadual do ICMS de cada UF + RICMS (alíquota geral, alíquotas majoradas/reduzidas por produto, FCP)
- **Modelo:** `key = [uf, ncm_or_cest_or_"*"]` → `{rate, fcp_rate, reduced_base_pct?, legal_basis}`; a linha `"*"` é a alíquota geral (MVP começa só com ela + FCP; refinamento por NCM depois)
- **Mudanças em 2026 (para a vigência):** AL 20,5% a partir de 01/04/2026; majorações em PI, PE, RJ; MA 23%, PI 22,5% — cada uma com `effective_from` próprio
- **Estratégia:** 27 alíquotas gerais + FCP é viável à mão em um dia; por-produto, só para o Sudeste (SP, MG, RJ, ES) no MVP

### 1.7 `icms_interstate_rate` — classe **D**

- **Fonte:** Resolução Senado 22/1989 (7%/12%) e 13/2012 (4% importados); EC 87/2015 (DIFAL)
- **Modelo:** `key = [origin_uf, destination_uf, origin_category]` → `{rate}`; 27×27×2 linhas geradas por script a partir das regras regionais
- **Frequência:** praticamente nunca (última: 2013); a reforma reduz gradualmente ICMS de 2029 a 2032

### 1.8 `cst_icms`, `csosn`, `cst_ipi`, `cst_pis_cofins` — classe **B/D**

- **Fonte:** Ajuste SINIEF 07/05 (CST ICMS / CSOSN, Tabela B); tabelas 4.3.1–4.3.4 do SPED (`sped.rfb.gov.br/pagina/show/1578`) para CST IPI/PIS/COFINS
- **Curadoria nossa:** coluna `taxation_kind` (taxed, exempt, st_withheld…) e `regime_allowed` (normal / simples) — base dos derivados `item.*.taxation_kind`
- **Frequência:** raríssima

### 1.9 `pis_cofins_special` — NCM monofásicos, alíquota zero, suspensão — classe **B**

- **Fonte:** tabelas 4.3.10 a 4.3.17 da EFD-Contribuições (Portal SPED, XLS); Lei 10.865/04, 10.147/00, etc.
- **Uso:** exceções da regra `PISCOFINS.CST.REGIME` (Lucro Real com CST 04/06 em NCM monofásico é correto)
- **Nota:** PIS/COFINS são extintos em 2027 (substituídos pela CBS); esta tabela ganha `effective_until: 2026-12-31`

### 1.10 `ibs_cbs_class` — CST IBS/CBS × cClassTrib × crédito presumido — classe **A**

- **Fonte oficial:** Portal DF-e SVRS: `https://dfe-portal.svrs.rs.gov.br/DFE/ClassificacaoTributaria` (online + JSON) e Portal NF-e → Documentos → Diversos. Informe Técnico 2025.002 (última v1.50; linhas atualizadas com LC 227/2026 marcadas com `DataAtualizacao = 23/01/2026`)
- **API:** `https://cff.svrs.rs.gov.br/api/v1/consultas/classTrib` (GET, JSON; **exige certificado ICP-Brasil** com autenticação mútua; recomendação oficial: 1 GET/dia). Roadmap da SVRS: crédito presumido, anexos, `indOp`
- **Conteúdo:** cClassTrib, CST, descrição, base legal (artigo da LC 214), `pRedAliq` (percentual de redução), indicadores (`indOp`, `indNFe`…), vigência
- **Automação:** job diário (certificado do próprio escritório-piloto ou o nosso) → diff → versão
- **Uso:** regra `IBSCBS.CST_CLASS.COHERENT`, `pRedAliq` esperado

### 1.11 `ibs_cbs_schedule` — cronograma de alíquotas — classe **D**

- **Fonte:** LC 214/2025 (Planalto, `lcp214.htm`) arts. 343–349 (transição); Resolução do Senado (alíquota de referência, **ainda não publicada** em 29/08/2026); estimativa CGIBS de 06/08/2026: 27,91% (IBS 18,70% + CBS 9,21%) — acima do teto de 26,5%, sujeita a PLP de redução
- **Modelo:** `key = [year, tax, uf?, city?]` → `{rate, kind: "test" | "reference" | "estimated", legal_basis}`
  - 2026: CBS 0,9% + IBS 0,1% (`test`)
  - 2027–2028: CBS alíquota de referência (`estimated` até a Resolução) + IBS 0,1% (`test`)
  - 2029–2032: IBS crescendo, ICMS/ISS reduzindo 10%/ano; 2033 integral
- **Regra de produto:** o simulador **mostra o `kind`** ao contador; alíquota `estimated` nunca gera `finding` de erro, só `info`

### 1.12 `sped_layout` — spec do leiaute EFD ICMS/IPI — classe **B**

- **Fonte:** Guia Prático EFD ICMS/IPI (Portal SPED → Manuais): v3.2.3 (06/05/2026) para leiaute **020** (vigência 01/01–31/12/2026, Ato COTEPE 79/2025, NT 2025.001); leiaute 019 para 2025
- **Conteúdo:** registros, campos, tipo, tamanho, obrigatoriedade, regras de validação, por leiaute
- **Automação:** extrair as tabelas do PDF (tabula/pdfplumber) para JSON → revisão; o formato do Guia é estável há anos
- **Importante:** leiaute 020 **não escritura IBS/CBS/IS** (documentos só com tributos novos não entram na EFD). Cross-check desses tributos é XML × XML até o SPED absorvê-los

### 1.13 `sped_codes` — tabelas 4.x/5.x do SPED — classe **B**

- **Fonte:** Portal SPED, Tabelas de Códigos (`/pagina/show/1578`) — nacionais (4.1.x, 4.3.x); e **por UF** (5.1.1 ajustes de apuração, 5.2 benefícios, 5.3 ajustes de documento, 5.4–5.8) no portal da SEFAZ de cada UF
- **Uso:** validação estrutural do SPED (`sped_structure`) e, futuramente, benefícios (5.2 × cenário)

### 1.14 `sintegra_layout` — classe **B**

- **Fonte:** Convênio ICMS 57/95 + Manual de Orientação vigente (CONFAZ, `CV057_95_manualOrien2`); validador nacional 5.0.2 (Conv. 76/03), `sintegra.gov.br`
- **Frequência:** praticamente congelado; vários estados já dispensam SINTEGRA para quem entrega EFD
- **Automação:** conversão única do manual → JSON; revisão anual

### 1.15 `nfe_layout` — mapeamento XML → canônico — classe **A/B**

- **Fonte:** Portal NF-e → Documentos → Esquemas XML (XSD) e Notas Técnicas. Estado atual: **NT 2025.002 v1.51 (01/08/2026)**; v1.40 (20/05/2026) fixou rejeição de DF-e sem IBS/CBS em produção a partir de **03/08/2026** (homologação desde 01/07/2026); ~206 regras de validação em produção, 170 condicionadas ao grupo
- **Uso:** o mapper do parser é código, mas as **datas de obrigatoriedade** (grupo IBS/CBS, `DFeReferenciado` por item em devoluções, etc.) são dados → vigência das regras
- **Frequência:** a NT teve 11 versões em 14 meses; monitorar a página de NTs mensalmente

---

## 2. Fontes de legislação (para `legal_references` das regras)

| Órgão | O quê | URL base |
|---|---|---|
| Planalto | LC 87/96 (Kandir), LC 123/06 (Simples), LC 214/2025 e LC 227/2026 (IBS/CBS/IS), Leis PIS/COFINS/IPI | `planalto.gov.br/ccivil_03/leis/lcp/` |
| CONFAZ | Convênios, Ajustes SINIEF, Protocolos ICMS (ST, CEST, CFOP, CST) | `confaz.fazenda.gov.br/legislacao/` |
| Senado | Resoluções 22/89, 13/2012 (alíquotas interestaduais); futura Resolução de alíquota de referência IBS/CBS | `senado.leg.br` |
| Portal NF-e (ENCAT/RFB) | Notas Técnicas, MOC, esquemas XML, tabelas (CFOP, cClassTrib) | `nfe.fazenda.gov.br/portal/` |
| Portal DF-e SVRS / Conformidade Fácil | Tabelas IBS/CBS (online, JSON, API), validador RTC | `dfe-portal.svrs.rs.gov.br`, `cff.svrs.rs.gov.br` |
| Portal SPED (RFB) | Guia Prático EFD, NTs, tabelas de códigos, EFD-Contribuições | `https://www.gov.br/sped/pt-br` (antigo `sped.rfb.gov.br`, desativado) |
| RFB | TIPI, IN sobre PIS/COFINS/IPI, alíquota de referência CBS (proposta ao TCU até 30/10/2026) | `gov.br/receitafederal` |
| CGIBS | Regulamento e alíquotas IBS, estimativas | site do Comitê Gestor |
| SEFAZ de cada UF | RICMS, alíquotas internas, ST, benefícios, tabelas 5.x do SPED | 27 portais (lista mantida em `catalog/uf_sources.yml`) |
| SINTEGRA | Convênio 57/95, manual, validador | `sintegra.gov.br` |

---

## 2b. Estado das tabelas (31/08/2026)

| Tabela | Situação | Cobertura / observações |
|---|---|---|
| `ncm` | ✅ importada (Siscomex JSON, 10.515 códigos, vigência por linha) | sync automático semanal (`Catalog::SyncJob`) |
| `tipi` | ✅ importada (xlsx oficial RFB, Decreto 11.158/22 até ADE 1/2026, 10.521 linhas + flag `has_ex`) | reimportar a cada ADE (classe B) |
| `cest` | ✅ importada (Convênio 142/18, anexos II–XXVI parseados, 1.591 CEST expandidos em 8.320 NCMs) | revisar a cada convênio alterador |
| `ibs_cbs_class` | ✅ importada (dataset `dadosOriginais` da página pública da SVRS — 18 CSTs, 164 cClassTrib com vigência e reduções; **sem certificado**) | sync automático diário |
| `pis_cofins_special` | ✅ gerada (Leis 10.147/00, 13.097/15, 9.718/98+10.560/02 expandidas por NCM = 389 códigos) | **pendente: autopeças (Lei 10.485/02)** |
| `st_uf` | ⚠️ parcial (SP × medicamentos, Portaria CAT 68/2019, 305 NCMs) | **cresce por demanda**: `Audit::Coverage` grava em cada run os pares UF×NCM consultados sem linha; `GET /admin/reference_tables/curation_queue` agrega (90 dias) e prioriza — cada linha nova exige base legal. Fornecedor de conteúdo segue como opção de escala |
| `icms_internal_rate` | ✅ geral: **27 UFs** (v2, vigência 2026-01-01, fontes cruzadas em 31/08/2026; FCP geral só RJ — AL/SE/PB têm fundo por produto, anotado) | ⚠️ por NCM: crescer pela fila de curadoria |
| demais (`cfop`, `cst_*`, `csosn`, `icms_interstate_rate`, `ibs_cbs_schedule`) | ✅ completas | classe D, mudanças raras |

## 3. Processo de atualização

**Implementado (31/08/2026):** `sidekiq-cron` (`config/schedule.yml`) roda `Catalog::SyncJob` (ncm semanal, ibs_cbs_class diário — cria versão **draft** apenas quando o conteúdo difere da vigente; publicar continua decisão humana com diff no painel) e `Catalog::ReviewReminderJob` (diário — registra em `audit_logs` as tabelas com `next_review_on` vencido ou sem versão; o painel de tabelas destaca em vermelho). `next_review_on` é definido por classe: A=90d (sanidade do sync), B=30d, C=90d, D=365d. Regras: alteração é sempre **nova versão** via painel (`draft → testing → shadow → published`), com casos de teste obrigatórios; `bin/rails rules:validate && bin/rails rules:test` no CI.

### 3.1 Rotina

| Cadência | Ação |
|---|---|
| Diária (job) | `ncm` (Siscomex), `ibs_cbs_class` (SVRS API) → diff automático; se houver mudança, cria versão `draft` e notifica admin |
| Mensal (checklist admin) | Página de NTs da NF-e; Portal SPED (Guia/NT); CONFAZ (últimos Convênios/Ajustes/Protocolos); ADEs de TIPI; notícias de alíquota interna por UF |
| Anual (dez/jan) | Novo leiaute EFD; virada do cronograma IBS/CBS; revisão das alíquotas gerais por UF (leis orçamentárias estaduais costumam mudar alíquota para o ano seguinte) |
| Por evento | Resolução do Senado (alíquota de referência); LC alterando LC 214; Convênio novo de ST/CEST |

### 3.2 Fluxo de uma versão

`import (auto/manual) → draft → diff revisado (o que entrou, saiu, mudou, com effective_from) → validação (regras/casos de teste que dependem da tabela rodam) → published`

Toda versão guarda `source_url`, `source_document` (cópia do PDF/JSON original no S3), `imported_by`, `notes`.

### 3.3 Sinais de desatualização vindos dos dados

O motor alimenta a curadoria: quando uma regra de escopo `scenario` acha que "muitos clientes discordam da tabela" (ex.: 80% das notas de vários emissores destacam ST num CEST que a tabela diz não ter ST na UF), gera um **curation alert** para o admin, não findings para os contadores. É o mecanismo de "estar um passo à frente" sem depender só de leitura de Diário Oficial.

### 3.4 Fornecedores de conteúdo (avaliar na fase 2)

Para `st_uf` e `icms_internal_rate` por produto, assinar uma base pronta (Systax, Mix Fiscal, IOB, e-Auditoria) pode custar menos que curar 27 UFs. A arquitetura já suporta: é só mais um importador com `source_type: platform` e `source: "vendor:x"`.

---

## 4. Pendências

- [x] **UFs prioritárias: Sudeste (SP, MG, RJ, ES)** — decidido em 29/08/2026. Escopo inicial de `st_uf` e `icms_internal_rate` por produto; demais UFs só alíquota geral + FCP. ES é relevante também por ser exceção na alíquota interestadual (12% mesmo vindo do Sul/Sudeste).
- [x] Certificado ICP-Brasil para a API da SVRS: **emitir um e-CNPJ A1 para a plataforma** (decidido em 29/08/2026). Guardar em KMS/Vault, nunca no banco; renovar anualmente.
- [ ] Testar o parser do Guia Prático (PDF → JSON) com os leiautes 019 e 020 antes de assumir classe B
- [x] Portal SPED migrou para **`https://www.gov.br/sped/pt-br`** (confirmado em 29/08/2026); as URLs `sped.rfb.gov.br` abaixo são históricas e devem ser trocadas ao escrever os importadores.
