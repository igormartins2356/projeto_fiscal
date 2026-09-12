# Canonical document — field dictionary

> O canônico é o **único** vocabulário que o motor de regras, o cross-check e o simulador enxergam. Parsers (NF-e 4.00, NF-e com grupos IBS/CBS/IS, NFC-e, eventos, SPED, SINTEGRA) escrevem nele; nada lê XML diretamente.
>
> Versão do esquema: **`schema_version: 1`**. Campos só são adicionados, nunca renomeados; remoção só com nova major.

---

## 0. Convenções

| Tema | Regra |
|---|---|
| Nomes | Identificadores em **inglês**, `snake_case`. Ficam em português apenas termos padronizados pela legislação: siglas (`cst`, `csosn`, `cfop`, `ncm`, `cest`, `crt`, `difal`, `fcp`, `icms`, `ipi`, `pis`, `cofins`, `ibs`, `cbs`, `is`), regimes (`simples_nacional`, `lucro_presumido`, `lucro_real`, `mei`) e nomes oficiais de campo de SPED/SINTEGRA. A coluna "XML" dá o mapeamento. |
| Caminhos | Regras referenciam campos por caminho pontilhado: `doc.issuer.uf`, `item.icms.cst`. |
| Decimais | `BigDecimal`, serializado como **string** no JSONB (`"12.50"`), nunca float. Escala do XML preservada. |
| Percentuais | Sempre em **percentual** como no XML (`18.00` = 18%), não fração. |
| Datas | `date` ISO (`2026-03-14`); data-hora com offset (`2026-03-14T10:22:00-03:00`). `dhEmi` guarda o offset original. |
| Ausência | Campo não presente no XML → **ausente** (chave inexistente), nunca `null` "falso". A DSL tem `present`/`absent`. Zero explícito no XML fica `"0.00"`. |
| Códigos | Strings, com zeros à esquerda preservados (`"0102"`, `"00"`, `"5102"`). |
| Enumerações derivadas | Strings minúsculas em inglês (`"sale_return"`, `"interstate"`), exceto termos legais. Lista fechada por campo, versionada com o esquema. |
| Origem | Todo campo derivado é marcado nesta doc com **[D]** e traz a regra de derivação na seção 8. Campos [D] que dependem de tabela do Catalog usam a versão vigente na `reference_date` do documento. |
| Pendências | **[P]** = campo previsto no canônico e **ainda não produzido** (o parser não mapeia ou a derivação não existe). Fica na doc porque o desenho já o reserva, mas regra nenhuma pode contar com ele: na prática o caminho está sempre ausente. Ao implementar, tirar o [P]. |

---

## 1. Raiz do documento (`doc`)

### 1.1 Identidade e proveniência

| Campo | Tipo | XML | Descrição |
|---|---|---|---|
| `schema_version` | int | — | versão do canônico |
| `kind` | enum | — | `nfe` \| `nfce` \| `event` \| `invalidation` (inutilização) |
| `model` | string | `ide/mod` | `"55"` NF-e, `"65"` NFC-e |
| `access_key` | string(44) | `infNFe/@Id` | chave de acesso; **identidade do documento** |
| `layout_version` | string | `infNFe/@versao` | `"4.00"` |
| `layout_groups` | string[] [D] | — | grupos opcionais presentes: `ibs_cbs`, `is`, `icms_uf_dest`, `payment`… |
| `xml_hash` | string | — | SHA-256 do XML bruto (idempotência) |
| `xml_ref` | string | — | caminho no storage |
| `environment` | enum | `ide/tpAmb` | `production` \| `homologation`; `tpAmb` ausente → chave ausente. Homologação e ambiente ausente são **pulados** na ingestão (`upload_batches.files_skipped` + motivo em `errors_log`) |
| `monitored_cnpj` | string | — | CNPJ do cliente do escritório ao qual o documento pertence |
| `role` [D] | enum | — | `issuer` \| `recipient` \| `third_party` (ver 8.1) |
| `reference_date` [D] | date | — | data para seleção de vigência: **data local** de `issuance.issued_at` (os 10 primeiros caracteres do `dhEmi`, preservando o offset da UF — nunca convertida para o fuso da aplicação). Documento sem `dhEmi` válido é recusado na ingestão |
| `period` [D] | string | — | `"2026-03"` (competência) |

### 1.2 Identificação (`doc.issuance`, `doc.operation`)

| Campo | Tipo | XML | Descrição |
|---|---|---|---|
| `issuance.issued_at` | datetime | `ide/dhEmi` | |
| `issuance.dispatched_at` | datetime | `ide/dhSaiEnt` | opcional (saída/entrada) |
| `issuance.series` | string | `ide/serie` | |
| `issuance.number` | int | `ide/nNF` | |
| `issuance.numeric_code` | string | `ide/cNF` | |
| `issuance.emission_type` | enum | `ide/tpEmis` | `normal` \| `contingency_fsda` \| `epec` \| `svc_an` \| `svc_rs` \| `offline_nfce` … |
| `issuance.purpose` | enum | `ide/finNFe` | `normal` \| `complementary` \| `adjustment` \| `return` |
| `issuance.process` **[P]** | enum | `ide/procEmi` | `taxpayer_app` \| `tax_authority_single` \| … — `procEmi` ainda não é mapeado pelo parser |
| `issuance.app_version` | string | `ide/verProc` | útil para agrupar erros por ERP |
| `operation.nature_text` | string | `ide/natOp` | texto livre do ERP |
| `operation.direction_declared` | enum | `ide/tpNF` | `inbound` \| `outbound` **do ponto de vista do emitente** |
| `operation.direction` [D] | enum | — | `inbound` \| `outbound` **do ponto de vista do CNPJ monitorado** (8.2) |
| `operation.scope` | enum | `ide/idDest` | `intrastate` \| `interstate` \| `foreign` |
| `operation.taxable_event_city_code` | string | `ide/cMunFG` | código IBGE |
| `operation.final_consumer` | bool | `ide/indFinal` | |
| `operation.presence` | enum | `ide/indPres` | `not_applicable` \| `in_person` \| `internet` \| `phone` \| `home_delivery` \| `in_person_off_premises` \| `other` |
| `operation.intermediary` | enum | `ide/indIntermed` | `none` \| `third_party_platform` |
| `operation.nature` [D] | enum | — | classificação a partir do CFOP predominante + purpose (8.3): `sale`, `sale_return`, `purchase_return`, `purchase`, `transfer`, `bonus`, `shipment`, `shipment_return`, `industrialization`, `export`, `import`, `adjustment`, `complementary`, `consignment`, `demonstration`, `warranty`, `other` |
| `operation.cfops` [D] | string[] | — | CFOPs distintos dos itens |
| `operation.mixed_cfop` [D] | bool | — | mais de um CFOP no documento |
| `operation.origin_uf` [D] | string | — | UF do emitente |
| `operation.destination_uf` [D] | string | — | UF do destinatário (ou `"EX"`) |

### 1.3 Referências (`doc.references[]`)

| Campo | Tipo | XML |
|---|---|---|
| `kind` | enum | `refNFe` → `nfe`; `refNF` → `nf_model_1`; `refCTe` → `cte`; `refECF` → `ecf`; `refNFP` → `producer_nf` |
| `access_key` | string | `NFref/refNFe` |
| `resolved` [D] | bool | documento referenciado existe na base do cliente |
| `document_id` [D] | id | id interno quando resolvida |
| `nf_model_1` | obj | `refNF/*` (UF, AAMM, CNPJ, mod, serie, nNF) quando aplicável |

### 1.4 Status e protocolo (`doc.status`, `doc.protocol`)

| Campo | Tipo | XML/Origem | Descrição |
|---|---|---|---|
| `status.state` [D] | enum | protocolo + eventos | `authorized` (cStat 100 e 150) \| `cancelled` \| `denied` \| `rejected` \| `no_protocol` |
| `status.cancelled_at` [D] | datetime | evento 110111/110112 | |
| `status.has_correction_letter` **[P]** | bool | evento 110110 | a CC-e é ingerida como documento `kind: event`, mas ainda não se projeta no `status` da nota alvo |
| `status.manifestation` **[P]** | enum | eventos 2102xx | `awareness` \| `confirmed` \| `unknown` \| `not_performed` — idem: evento ingerido, projeção não implementada |
| `protocol.number` | string | `protNFe/nProt` | |
| `protocol.received_at` | datetime | `protNFe/dhRecbto` | |
| `protocol.status_code` | string | `protNFe/cStat` | `"100"` autorizada, `"110"`/`"301"`/`"302"` denegada… |
| `protocol.digest` | string | `protNFe/digVal` | |

---

## 2. Partes

### 2.1 Emitente (`doc.issuer`)

| Campo | Tipo | XML |
|---|---|---|
| `cnpj` / `cpf` | string | `emit/CNPJ` \| `emit/CPF` |
| `legal_name` | string | `emit/xNome` |
| `trade_name` | string | `emit/xFant` |
| `ie` | string | `emit/IE` |
| `ie_st` | string | `emit/IEST` |
| `im` | string | `emit/IM` |
| `cnae` | string | `emit/CNAE` |
| `crt` | string | `emit/CRT` (`"1"` Simples, `"2"` Simples excesso sublimite, `"3"` Regime normal, `"4"` MEI) |
| `tax_regime` [D] | enum | `simples_nacional` \| `simples_nacional_excess` \| `normal` \| `mei` (8.4) |
| `address.*` | obj | `enderEmit/*` → `street, number, complement, district, city_code, city, uf, zip_code, country_code, country, phone` |
| `uf` | string | atalho de `address.uf` |

### 2.2 Destinatário (`doc.recipient`)

| Campo | Tipo | XML |
|---|---|---|
| `cnpj` / `cpf` / `foreign_id` | string | `dest/CNPJ` \| `dest/CPF` \| `dest/idEstrangeiro` |
| `legal_name` | string | `dest/xNome` |
| `ie_indicator` | enum | `dest/indIEDest`: `"1"` → `taxpayer`, `"2"` → `exempt`, `"9"` → `non_taxpayer` |
| `ie` | string | `dest/IE` |
| `isuf` | string | `dest/ISUF` |
| `im` | string | `dest/IM` |
| `email` | string | `dest/email` |
| `address.*` | obj | `enderDest/*` (mesmos subcampos do emitente) |
| `uf` | string | atalho; `"EX"` se exterior |
| `person_type` [D] | enum | `legal_entity` \| `individual` \| `foreign` \| `unidentified` (NFC-e sem dest) |
| `icms_taxpayer` [D] | bool | `ie_indicator == taxpayer` |

### 2.3 Outros participantes (opcionais)

- **[P]** `doc.pickup`, `doc.delivery`: `{cnpj|cpf, address.*}` — `retirada/*`, `entrega/*`.
- **[P]** `doc.authorized_xml_parties[]`: `autXML/CNPJ|CPF`.
- **[P]** `doc.intermediary`: `{cnpj, identifier}` — `infIntermed/*` (o indicador `ide/indIntermed` é mapeado em `operation.intermediary`; o grupo com CNPJ/identificador não).
- `doc.technical_responsible`: `{cnpj, contact, email, phone}` — `infRespTec/*`. Útil para identificar o ERP emissor.

---

## 3. Transporte, cobrança e pagamento

### 3.1 `doc.transport`

| Campo | XML |
|---|---|
| `freight_mode` | `transp/modFrete` → `issuer_cif` (0), `recipient_fob` (1), `third_party` (2), `own_sender` (3), `own_recipient` (4), `no_freight` (9) |
| `carrier.{cnpj|cpf, name, ie, address, city, uf}` | `transporta/*` |
| `icms_withholding.{service_amount, base_amount, rate, amount, cfop, city_code}` **[P]** | `retTransp/*` |
| `vehicle.{plate, uf, rntc}` **[P]** | `veicTransp/*` |
| `volumes[].{quantity, kind, brand, numbering, net_weight, gross_weight}` | `vol/*` |

### 3.2 `doc.billing` — **[P]** (grupo `cobr` ainda não mapeado)

- `invoice.{number, original_amount, discount_amount, net_amount}` — `cobr/fat/*`
- `installments[].{number, due_date, amount}` — `cobr/dup/*`

### 3.3 `doc.payments[]` (obrigatório em NFC-e; presente em NF-e 4.00)

| Campo | XML |
|---|---|
| `timing` | `detPag/indPag` → `cash` \| `installment` |
| `method` | `detPag/tPag` (código `"01"` dinheiro … `"17"` PIX, `"90"` sem pagamento) |
| `method_description` | `detPag/xPag` |
| `amount` | `detPag/vPag` |
| `card.{integration_type, acquirer_cnpj, brand, authorization}` | `card/*` |
| `doc.change_amount` **[P]** | `pag/vTroco` |

---

## 4. Totais (`doc.totals`)

Todos `decimal`. Fonte `total/ICMSTot/*` salvo indicação.

| Campo | XML |
|---|---|
| `icms_base` | `vBC` |
| `icms` | `vICMS` |
| `icms_exempted` | `vICMSDeson` |
| `fcp` | `vFCP` |
| `icms_st_base` | `vBCST` |
| `icms_st` | `vST` |
| `fcp_st` | `vFCPST` |
| `fcp_st_withheld` | `vFCPSTRet` |
| `fcp_uf_dest_base` / `fcp_uf_dest` | `vBCFCPUFDest` / `vFCPUFDest` |
| `icms_uf_dest` | `vICMSUFDest` |
| `icms_uf_sender` | `vICMSUFRemet` |
| `products` | `vProd` |
| `freight` / `insurance` / `discount` / `other_expenses` | `vFrete` / `vSeg` / `vDesc` / `vOutro` |
| `ii` | `vII` |
| `ipi` / `ipi_returned` | `vIPI` / `vIPIDevol` |
| `pis` / `cofins` | `vPIS` / `vCOFINS` |
| `total` | `vNF` |
| `approx_taxes` | `vTotTrib` |
| `issqn.*` **[P]** | `total/ISSQNtot/*` (se houver item de serviço) — fora de escopo de regras, ainda não mapeado |
| `withholdings.{pis, cofins, csll, irrf, irrf_base, social_security_base, social_security}` | `total/retTrib/*` |
| `ibs_cbs.*` | `total/IBSCBSTot/*` — ver 5.9 |
| **Derivados** | |
| `items_sum.{products, icms_base, icms, icms_st, ipi, pis, cofins, discount, freight, ibs, cbs, is}` [D] | soma dos itens com `included_in_total = true` |
| `totals_mismatch` [D] | obj `{field: difference}` só para campos onde `|total - items_sum| > 0` (a tolerância é da regra; aqui é o valor cru) |

---

## 5. Item (`item`) — `det[]`

### 5.1 Identificação e produto (`item.product`)

| Campo | Tipo | XML |
|---|---|---|
| `item.number` | int | `det/@nItem` |
| `product.code` | string | `prod/cProd` |
| `product.gtin` / `product.taxable_gtin` | string | `prod/cEAN` / `prod/cEANTrib` (`"SEM GTIN"` normalizado para ausente + `no_gtin: true`) |
| `product.description` | string | `prod/xProd` |
| `product.ncm` | string(8) | `prod/NCM` |
| `product.nve[]` | string[] | `prod/NVE` |
| `product.cest` | string(7) | `prod/CEST` |
| `product.scale_indicator` | enum | `prod/indEscala` → `relevant` \| `not_relevant` |
| `product.manufacturer_cnpj` | string | `prod/CNPJFab` |
| `product.benefit_code` | string | `prod/cBenef` |
| `product.ex_tipi` | string | `prod/EXTIPI` |
| `product.cfop` | string(4) | `prod/CFOP` |
| `product.commercial_unit` / `commercial_quantity` / `commercial_unit_price` | string / decimal / decimal | `uCom` / `qCom` / `vUnCom` |
| `product.taxable_unit` / `taxable_quantity` / `taxable_unit_price` | | `uTrib` / `qTrib` / `vUnTrib` |
| `product.gross_amount` | decimal | `prod/vProd` |
| `product.freight` / `insurance` / `discount` / `other_expenses` | decimal | `vFrete` / `vSeg` / `vDesc` / `vOutro` |
| `product.included_in_total` | bool | `prod/indTot` |
| `product.purchase_order` / `product.purchase_order_item` | string / int | `xPed` / `nItemPed` |
| `product.fci` | string | `prod/nFCI` |
| `product.used_movable_good` | bool | `prod/indBemMovelUsado` (NT 2025.002) |
| `product.batches[]` **[P]** | obj[] | `prod/rastro/*` (lot, quantity, manufactured_on, expires_on) |
| `product.specific_detail` **[P]** | obj | `veicProd` \| `med` \| `arma` \| `comb` \| … com `kind` |
| `product.import_declarations[]` **[P]** | obj[] | `prod/DI/*` |
| `product.export_detail` **[P]** | obj | `prod/detExport/*` |
| `item.additional_info` | string | `det/infAdProd` |
| `item.approx_taxes` | decimal | `imposto/vTotTrib` |

**Derivados do item [D]** (8.5):

| Campo | Descrição |
|---|---|
| `item.net_amount` | `gross_amount - discount + freight + insurance + other_expenses` |
| `item.cfop_nature` | natureza do CFOP pela tabela `cfop` do Catalog (`sale`, `sale_return`, …); CFOP fora da tabela → `"unknown"` |
| `item.cfop_known` | CFOP existe na tabela `cfop` vigente |
| `item.cfop_st_role` | papel do CFOP na ST pela tabela `cfop`: `substitute` (retém) \| `substituted` (ST já retida) \| `st_other` (operação com ST em que o CST correto depende do caso: 5.402 entre substitutos do mesmo produto, 5.408/5.409 transferência, 5.414/5.415 remessa para venda fora do estabelecimento — nenhuma regra de ST julga) \| `none` (fora da tabela → `"unknown"`) |
| `item.cfop_requires_reference` | CFOP exige documento referenciado (devolução, complementar); só gravado quando a linha existe |
| `item.cfop_own_production` | CFOP de saída de produção do estabelecimento; só gravado quando a linha existe |
| `item.cfop_group` | primeiro dígito: `inbound_intrastate` (1), `inbound_interstate` (2), `inbound_foreign` (3), `outbound_intrastate` (5), `outbound_interstate` (6), `outbound_foreign` (7) |
| `item.cfop_scope` | `intrastate` \| `interstate` \| `foreign` (a partir de `cfop_group`) |
| `item.ncm_valid` | NCM existe na tabela `ncm` vigente na `reference_date` |
| `item.ncm_chapter` | 2 primeiros dígitos |
| `item.ncm_generic` | `"00000000"` ou `"00"` |
| `item.expected_cest` | CEST(s) para o NCM na tabela `cest` (pode ser lista) |
| `item.st_applicable_by_catalog` | NCM/CEST está no regime de ST da `destination_uf` (tabela `st_uf`, busca por NCM → NCM de 4 dígitos → CEST do item), antes de overrides de cenário; ausente quando a UF não tem curadoria |
| `item.is_service` | grupo `ISSQN` presente |
| `item.has_difal` | grupo `ICMSUFDest` presente (ver 5.4) |

### 5.2 ICMS (`item.icms`) — `imposto/ICMS/ICMSxx`

| Campo | Tipo | XML | Descrição |
|---|---|---|---|
| `group` | string | nome do elemento | `ICMS00`, `ICMS10`, `ICMS20`, `ICMS30`, `ICMS40`, `ICMS51`, `ICMS60`, `ICMS70`, `ICMS90`, `ICMSPart`, `ICMSST`, `ICMSSN101`… `ICMSSN900` |
| `origin` | string(1) | `orig` | `0`–`8` |
| `origin_category` [D] | enum | — | chave da alíquota interestadual de 4% da **Res. SF 13/2012**: `imported` para origem `1, 2, 3, 8`; `domestic` para `0, 4, 5, 6, 7`. O nome engana: origens 6 e 7 (bem importado/com conteúdo importado **sem similar nacional**, lista CAMEX) são estrangeiras e mesmo assim saem como `domestic`, porque estão fora da Res. 13/2012 e seguem 7%/12% |
| `cst` | string(2) | `CST` | presente só em regime normal |
| `csosn` | string(3) | `CSOSN` | presente só no Simples |
| `situation_code` [D] | string | — | `cst` ou `csosn`, o que existir |
| `situation_field` [D] | enum | — | `cst` \| `csosn` \| `absent` |
| `base_mode` | string | `modBC` | `0` MVA, `1` pauta, `2` preço tabelado, `3` valor operação |
| `base_reduction_pct` | decimal | `pRedBC` | |
| `base_amount` | decimal | `vBC` | |
| `rate` | decimal | `pICMS` | |
| `amount` | decimal | `vICMS` | |
| `fcp.{base_amount, rate, amount}` | decimal | `vBCFCP`, `pFCP`, `vFCP` | |
| `exemption.{amount, reason_code, deducts}` | | `vICMSDeson`, `motDesICMS`, `indDeduzDeson` | |
| `deferral.{pct, operation_amount, deferred_amount}` | | `pDif`, `vICMSOp`, `vICMSDif` | ICMS51 |
| `simples_credit.{rate, amount}` | | `pCredSN`, `vCredICMSSN` | CSOSN 101/201/900 |
| `expected_base_amount` [D] | decimal | — | `(item.net_amount + IPI) × (1 - base_reduction_pct/100)`, só quando `base_mode` existe. O IPI entra na base **apenas** em operação a consumidor final / não contribuinte (LC 87/96 art. 13 §2, a contrario: na venda a contribuinte para industrialização ou comercialização o IPI fica fora) |
| `expected_base_reliable` [D] | bool | — | `false` quando `base_mode` ≠ 3 (pauta/MVA não deriva de valor) |
| `expected_amount` [D] | decimal | — | `base_amount × rate / 100` |
| `taxation_kind` [D] | enum | — | classificação do CST/CSOSN pela tabela `cst_icms`/`csosn` do Catalog: `taxed`, `taxed_with_st`, `reduced_base`, `exempt`, `not_taxed`, `suspended`, `deferred`, `st_withheld`, `simples_with_credit`, `simples_without_credit`, `other`… |
| `highlights_icms` [D] | bool | — | `amount > 0` |

### 5.3 ICMS-ST (`item.icms_st`) — mesmo grupo `ICMSxx`, campos ST

| Campo | XML |
|---|---|
| `base_mode` | `modBCST` |
| `mva_pct` | `pMVAST` |
| `base_reduction_pct` | `pRedBCST` |
| `base_amount` / `rate` / `amount` | `vBCST` / `pICMSST` / `vICMSST` |
| `fcp.{base_amount, rate, amount}` | `vBCFCPST` / `pFCPST` / `vFCPST` |
| `withheld.{base_amount, final_consumer_rate, amount, substitute_amount}` | `vBCSTRet` / `pST` / `vICMSSTRet` / `vICMSSubstituto` (CST 60 / CSOSN 500) |
| `withheld.fcp.{base_amount, rate, amount}` | `vBCFCPSTRet` / `pFCPSTRet` / `vFCPSTRet` |
| `exemption.{amount, reason_code}` | `vICMSSTDeson` / `motDesICMSST` |
| `st_uf` / `st_uf_base_pct` / `st_uf_amount` **[P]** | `UFST` / `pBCOp` / … (grupo `ICMSPart`, ainda não mapeado) |
| `highlights_st` [D] | `amount > 0` |
| `has_withheld_st` [D] | `withheld.amount` presente |
| `expected_base_amount` [D] | `(item.net_amount + IPI) × (1 + mva_pct/100) × (1 - base_reduction_pct/100)`, só quando há `mva_pct` e `base_mode = 4` (MVA) |
| `expected_amount` [D] | `base_amount × rate/100 − ICMS próprio destacado` (LC 87/96 art. 8º §5). **Não é derivado quando o item usa CSOSN**: o substituto optante do Simples não destaca ICMS próprio na nota e deduz a alíquota que *seria* devida (Conv. ICMS 35/2011), valor que não está no XML — tratar a ausência como zero inflava o esperado e apontava erro em ST correta |

### 5.4 DIFAL / partilha (`item.icms_uf_dest`) — `imposto/ICMSUFDest`

| Campo | XML |
|---|---|
| `base_amount` | `vBCUFDest` |
| `fcp.{base_amount, rate, amount}` | `vBCFCPUFDest` / `pFCPUFDest` / `vFCPUFDest` |
| `destination_internal_rate` | `pICMSUFDest` |
| `interstate_rate` | `pICMSInter` |
| `sharing_pct` | `pICMSInterPart` |
| `destination_amount` / `sender_amount` | `vICMSUFDest` / `vICMSUFRemet` |
| `expected_destination_amount` [D] | `base_amount × (destination_internal_rate − interstate_rate) / 100` (EC 87/2015, partilha integral ao destino desde 2019) |
| `item.has_difal` [D] | grupo presente |

### 5.5 IPI (`item.ipi`) — `imposto/IPI`

| Campo | XML |
|---|---|
| `producer_cnpj` / `seal.{code, quantity}` / `framing_code` | `CNPJProd` / `cSelo`,`qSelo` / `cEnq` |
| `cst` | `IPITrib/CST` ou `IPINT/CST` |
| `taxed` [D] | grupo `IPITrib` presente |
| `base_amount` / `rate` / `amount` | `vBC` / `pIPI` / `vIPI` |
| `quantity` / `unit_amount` | `qUnid` / `vUnid` (alíquota específica) |
| `expected_amount` [D] | `base_amount × rate / 100` |
| `cst_direction` [D] | `inbound` \| `outbound` pela tabela `cst_ipi` (Tabela 4.3.2 do SPED: 00–49 entrada, 50–99 saída) |
| `taxation_kind` [D] | `taxed`, `exempt`, `not_taxed`, `immune`, `suspended`, `other` pela tabela `cst_ipi` |

### 5.6 II (`item.ii`) — **[P]** (grupo `imposto/II` ainda não mapeado)

`base_amount, customs_expenses, amount, iof` — `vBC, vDespAdu, vII, vIOF`.

### 5.7 PIS e COFINS (`item.pis`, `item.cofins`, `item.pis_st`, `item.cofins_st`)

| Campo | XML |
|---|---|
| `group` | `PISAliq` \| `PISQtde` \| `PISNT` \| `PISOutr` (idem COFINS) |
| `cst` | `CST` |
| `base_amount` / `rate` / `amount` | `vBC` / `pPIS` / `vPIS` |
| `base_quantity` / `unit_rate` | `qBCProd` / `vAliqProd` |
| `expected_amount` [D] | `base_amount × rate/100` ou `base_quantity × unit_rate` |
| `taxation_kind` [D] | pela tabela `cst_pis_cofins`: `taxed`, `single_phase`, `zero_rate`, `exempt`, `no_incidence`, `suspended`, `other`, `st` |
| `cst_direction` [D] | pela tabela `cst_pis_cofins` (Tabela 4.3.3 do SPED): CST 01–49 → `outbound`, 50–99 → `inbound`; CST fora da tabela → `"unknown"` |
| `*_st.{base_amount, rate, amount, base_quantity, unit_rate, add_to_total}` | `PISST/*`, `COFINSST/*` (`indSomaPISST`) |

### 5.8 ISSQN (`item.issqn`) — apenas para registro; fora de escopo de regras

O parser grava só a **presença** do grupo: `issqn.present = true` (é o que sustenta o derivado `item.is_service`).

**[P]** os campos do grupo: `base_amount, rate, amount, taxable_event_city_code, service_list_item, unconditional_discount, conditional_discount, withholding, iss_indicator, service_code, incidence_city_code, country_code, process_number, tax_incentive`.

### 5.9 IBS / CBS / IS (`item.ibs_cbs`, `item.is`) — NT 2025.002 (grupos `IBSCBS`, `IS`)

> Mapeamento conforme a versão vigente da NT; nomes abaixo são canônicos e estáveis mesmo que o XML mude.

| Campo | XML (NT 2025.002) | Descrição |
|---|---|---|
| `ibs_cbs.present` [D] | — | grupo existe |
| `ibs_cbs.cst` | `IBSCBS/CST` | 3 dígitos (`000`, `010`, `011`, `200`, `210`, `220`, `221`, `400`, `410`, `510`, `550`, `620`, `800`, `810`, `820`, `830`…) |
| `ibs_cbs.class_code` | `IBSCBS/cClassTrib` | 6 dígitos (cClassTrib) |
| `ibs_cbs.base_amount` | `gIBSCBS/vBC` | |
| `ibs_cbs.ibs_uf.{rate, deferral_pct, deferral_amount, refund_amount, reduction_pct, effective_rate, amount}` | `gIBSUF/*` (`pIBSUF, pDif, vDif, vDevTrib, pRedAliq, pAliqEfet, vIBSUF`) | |
| `ibs_cbs.ibs_city.{…mesmos…}` | `gIBSMun/*` | |
| `ibs_cbs.ibs.amount` | `vIBS` | soma UF + município |
| `ibs_cbs.cbs.{rate, deferral_pct, deferral_amount, refund_amount, reduction_pct, effective_rate, amount}` | `gCBS/*` | |
| `ibs_cbs.regular_taxation.{cst, class_code, ibs_uf_rate, ibs_city_rate, cbs_rate, ibs_uf_amount, ibs_city_amount, cbs_amount}` | `gTribRegular/*` | "quanto seria" sem o benefício |
| `ibs_cbs.presumed_credit.{ibs: {code, pct, amount}, cbs: {code, pct, amount}}` | `gIBSCredPres`, `gCBSCredPres` | |
| `ibs_cbs.single_phase.present` | `gIBSCBSMono` | combustíveis; o parser grava só `{present: true}` — os campos do grupo são **[P]** |
| `ibs_cbs.government_purchase.{…}` **[P]** | `gCompraGov` | |
| `ibs_cbs.cbs.expected_amount` [D] / `ibs_cbs.ibs_uf.expected_amount` [D] / `ibs_cbs.ibs_city.expected_amount` [D] | — | `base_amount × effective_rate/100`, por grupo que tenha `effective_rate`. **Não existe `ibs_cbs.ibs.expected_amount`**: `ibs` carrega só o `vIBS` do XML (soma UF + município) |
| `ibs_cbs.schedule_rates.{ibs_uf, ibs_city, cbs}` [D] | — | alíquotas da tabela `ibs_cbs_schedule` pelo **ano** da `reference_date`; grupo ausente quando o ano não está na tabela |
| `is.{cst, class_code, base_amount, rate, specific_rate, quantity, unit, amount}` | `IS/*` (`CSTIS, cClassTribIS, vBCIS, pIS, pISEspec, qTrib, uTrib, vIS`) | Imposto Seletivo |
| `doc.totals.ibs_cbs.{base_amount, ibs_uf, ibs_city, ibs, cbs, presumed_credit_ibs, presumed_credit_cbs, is}` | `IBSCBSTot/*` | totais |
| `doc.ibs_cbs.taxable_event_city_code` | `ide/cMunFGIBS` | |
| `doc.ibs_cbs.debit_note_type` / `credit_note_type` | `ide/tpNFDebito` / `ide/tpNFCredito` | |
| `doc.ibs_cbs.prepayments[]` **[P]** | `gPagAntecipado/refNFe` | |
| `item.ibs_cbs.return_references[]` **[P]** | `refNFe` do item quando a NT exigir | |

---

## 6. Informações adicionais (`doc.additional_info`)

- `tax_authority`: `infAdic/infAdFisco`
- `complementary`: `infAdic/infCpl`
- **[P]** `taxpayer_notes[]`: `obsCont/{field, text}`
- **[P]** `tax_authority_notes[]`: `obsFisco/{field, text}`
- **[P]** `referenced_processes[]`: `procRef/{number, origin}`
- **[P]** `export.{shipping_uf, shipping_place, dispatch_place}`: `exporta/*`
- **[P]** `purchase.{commitment_note, order, contract}`: `compra/*`

---

## 7. Eventos e inutilização

Eventos são documentos próprios (`kind: event`) **e** projetam-se no `doc.status` da nota alvo.

| Campo | XML |
|---|---|
| `access_key` | `infEvento/chNFe` (nota alvo) |
| `event.code` | `infEvento/tpEvento` |
| `event.kind` [D] | `cancellation` (110111), `cancellation_by_replacement` (110112), `correction_letter` (110110), `epec` (110140), `awareness` (210210), `confirmation` (210200), `unknown_operation` (210220), `operation_not_performed` (210240), `interested_party` (110150), `delivery_receipt` (110130)… |
| `event.sequence` | `nSeqEvento` |
| `event.occurred_at` | `dhEvento` |
| `event.author` | `CNPJ`/`CPF` |
| `event.justification` | `detEvento/xJust` |
| `event.correction_text` | `detEvento/xCorrecao` |
| `event.referenced_protocol` | `detEvento/nProt` |
| `event.replacement_access_key` | 110112: chave da NFC-e substituta |
| `protocol.*` | `retEvento/infEvento/{nProt, dhRegEvento, cStat}` |

**Inutilização** (`kind: invalidation`): `{cnpj, model, series, first_number, last_number, year, justification, protocol}` — `inutNFe/infInut/*`. Alimenta a primitiva de lacuna de numeração.

---

## 8. Regras de derivação

Derivação roda **na normalização** e é re-executável (`Ingestion::Rederive`, via `Ingestion::RederiveJob` ou `rake 'ingestion:rederive[client_id,period]'`) quando muda tabela do Catalog ou chegam eventos/referências; a rederivação reexecuta também o `ReferenceResolver`. Derivados que dependem do Catalog guardam em `documents.catalog_versions` as versões usadas.

**Tabela indisponível ≠ "não"**: derivado que depende de tabela do Catalog só é gravado quando existe versão publicada vigente na `reference_date`; sem versão, a chave fica **ausente** ("não sei") e a regra que dependia dela simplesmente não se aplica. Com a tabela disponível e o código inexistente nela, os enums ficam `"unknown"` (e `cfop_known = false`), enquanto os booleanos derivados da linha (`cfop_requires_reference`, `cfop_own_production`) ficam ausentes.

**8.1 `doc.role`**
`issuer` se `issuer.cnpj == monitored_cnpj`; `recipient` se `recipient.cnpj == monitored_cnpj`; senão `third_party` — documento de terceiro não é importado: entra em `upload_batches.files_skipped` com o motivo em `errors_log`.

**8.2 `doc.operation.direction`**
`role = issuer` → `direction = direction_declared`. `role = recipient` → inverte (`outbound` do emitente é `inbound` para nós). Nota de entrada emitida por nós (`direction_declared = inbound`, ex.: devolução de cliente PF) mantém `inbound`.

**8.3 `doc.operation.nature`**
1. Se `issuance.purpose` ∈ {`return`, `complementary`, `adjustment`} → esse valor (`return` refinado em `sale_return`/`purchase_return` pelo CFOP).
2. Senão, natureza do CFOP predominante (por `net_amount`) via tabela `cfop.nature`.
3. Se CFOPs de naturezas diferentes → `mixed_cfop = true` e natureza do predominante.

**8.4 `doc.issuer.tax_regime`**
`crt`: `1`→`simples_nacional`, `2`→`simples_nacional_excess`, `3`→`normal`, `4`→`mei`. Ausente → `unknown`. (O regime *do cliente* vem do cenário; este é o que a nota declara — a divergência entre os dois é regra.)

**8.5 Derivados de item**
- `net_amount = gross_amount - discount + freight + insurance + other_expenses`.
- `cfop_group` e `cfop_scope` saem do primeiro dígito (não dependem de tabela); `cfop_nature`, `cfop_known`, `cfop_st_role`, `cfop_requires_reference`, `cfop_own_production`: tabela `cfop` vigente.
- `ncm_valid`, `expected_cest`, `st_applicable_by_catalog`: tabelas `ncm`, `cest`, `st_uf` vigentes na `reference_date`. O `st_uf` é consultado por `[destination_uf, NCM]`, depois `[destination_uf, NCM de 4 dígitos]`, depois `[destination_uf, CEST do item]`; sem `destination_uf`, pela UF do emitente. Sem linha, o derivado fica ausente (a UF pode simplesmente não estar curada).
- `icms.expected_base_amount = (net_amount + IPI a consumidor final) × (1 - base_reduction_pct/100)` (LC 87/96 art. 13 §2); `expected_base_reliable = false` quando `base_mode` ≠ 3 (pauta/MVA/preço tabelado não derivam do valor da operação).
- `*.expected_amount = base_amount × rate/100` (`ROUND_HALF_UP`, 2 casas). A tolerância é parâmetro da regra. Exceção: `icms_st.expected_amount` deduz o ICMS próprio destacado e **não é derivado** em item com CSOSN (5.3).
- `icms.taxation_kind`, `pis`/`cofins.taxation_kind` e `cst_direction`, `ipi.taxation_kind` e `cst_direction`: tabelas `cst_icms`/`csosn`/`cst_pis_cofins`/`cst_ipi`.
- `ibs_cbs.schedule_rates`: tabela `ibs_cbs_schedule` por ano de `reference_date` (+ UF/município quando a tabela tiver).

> Alíquota interna do Catalog (`icms_internal_rate`): a coluna `rate` é a alíquota do ICMS **sem** o FCP, que fica em `fcp_rate` — o adicional de fundo de combate à pobreza é destacado à parte no XML (`pFCP`/`vFCP`), e somá-lo à alíquota apontaria erro em nota correta.

**8.6 `doc.status`**
Base pelo `protocol.status_code` (`100` e `150` → `authorized` — 150 é "autorizada fora de prazo", nota válida; `110/301/302/303` → `denied`; qualquer outro código → `rejected`; ausente → `no_protocol`). Evento 110111/110112 autorizado → `cancelled`. Recalculado a cada evento ingerido.

**8.7 `doc.references[].resolved`**
Busca pela chave dentro do mesmo `monitored_cnpj` (`Ingestion::ReferenceResolver`, nos dois sentidos). Recalculado quando o documento referenciado chega depois e a cada rederivação — a derivação em si nunca sobrescreve um `resolved` já existente.

---

## 9. Arquivos fiscais (SPED EFD ICMS/IPI e SINTEGRA)

O canônico de arquivo é **registro-orientado**, guiado pela spec de leiaute do Catalog (`sped_layout`, `sintegra_layout` — versão vigente pela data do período):

```
fiscal_file: {kind: sped_icms_ipi | sintegra, layout_version, period_start, period_end,
              cnpj, ie, uf, purpose (original | rectifying), hash, ref}
record:      {line_number, block, record_type ("C100"), fields: {FIELD_NAME: value…},
              parent_id, children_ids[], document_access_key (quando o registro identifica um doc),
              document_id [D], item_number [D]}
```

- Campos usam o **nome oficial** do leiaute (`CHV_NFE`, `VL_DOC`, `CST_ICMS`, `VL_BC_ICMS`) — não traduzimos, porque o contador e o validador oficial falam nesse nome.
- Vínculo: `C100.CHV_NFE` ↔ `doc.access_key`; `C170.NUM_ITEM` ↔ `item.number`; SINTEGRA `50/54` ↔ por `(cnpj, model, series, number)` + item.
- O cross-check é uma primitiva de escopo `period` que recebe `fiscal_file + documents do período` e produz apontamentos com `record` **e** `document/item` de origem.

---

## 10. Contexto de avaliação (o que a DSL enxerga)

| Escopo | Variáveis disponíveis |
|---|---|
| `item` | `item`, `doc`, `scenario`, `params`, `let` (`lookup`/`calc`/`ref`) |
| `document` | `doc` (com `doc.items[]`), `scenario`, `params`, `let` |
| `cross_document` | `period.{documents[], events[], invalidations[]}`, `scenario`, `params` |
| `period` | `period.*` **e** `fiscal_file` (registros da EFD), `scenario`, `params` |
| `scenario` | `period.*`, `scenario`, `stats` (estatísticas prontas), `params` |

O catálogo não é um caminho do contexto: a regra consulta tabela por `let: [{"lookup": …}]`, que devolve a linha vigente na `reference_date` como variável (`DSL_RULES.md` §3.4).

`scenario` é o **cenário resolvido** do cliente para a data do documento (`Scenario::TaxScenario.resolve`): `tax_regime, simples_annex, uf, city_code, icms_taxpayer, ipi_taxpayer, iss_taxpayer, activity[], cnae, sells_to_final_consumer, uses_nfce, exports, imports, st.{source, applies, overrides[]}, benefits[], pis_cofins.regime, ibs_cbs.regime` — modelagem detalhada em `DSL_RULES.md` §7. Cliente sem cenário publicado na data: as regras que leem `scenario.*` não são avaliadas e o run registra um `evaluation_error` explicando (nunca um finding).

---

## 11. Exemplo (recorte)

```json
{
  "schema_version": 1, "kind": "nfe", "model": "55",
  "access_key": "35260312345678000190550010000012341000012345",
  "layout_version": "4.00", "layout_groups": ["ibs_cbs", "payment"],
  "monitored_cnpj": "12345678000190", "role": "issuer",
  "reference_date": "2026-03-14", "period": "2026-03",
  "issuance": {"issued_at": "2026-03-14T10:22:00-03:00", "series": "1", "number": 1234, "purpose": "return"},
  "operation": {"direction_declared": "inbound", "direction": "inbound", "scope": "intrastate", "final_consumer": false,
                "nature": "sale_return", "cfops": ["1202"], "mixed_cfop": false,
                "origin_uf": "SP", "destination_uf": "SP"},
  "references": [{"kind": "nfe", "access_key": "3526...", "resolved": true, "document_id": 9981}],
  "issuer": {"cnpj": "12345678000190", "uf": "SP", "crt": "1", "tax_regime": "simples_nacional"},
  "recipient": {"cnpj": "99887766000155", "uf": "SP", "ie_indicator": "taxpayer", "icms_taxpayer": true},
  "status": {"state": "authorized"},
  "totals": {"products": "1000.00", "total": "1000.00", "icms_base": "0.00", "icms": "0.00",
             "items_sum": {"products": "1000.00"}, "totals_mismatch": {}},
  "items": [{
    "number": 1,
    "product": {"code": "A1", "description": "Produto A", "ncm": "84713012", "cfop": "1202",
                "commercial_quantity": "2.0000", "commercial_unit_price": "500.00", "gross_amount": "1000.00",
                "discount": "0.00", "included_in_total": true},
    "net_amount": "1000.00", "cfop_nature": "sale_return", "cfop_group": "inbound_intrastate",
    "ncm_valid": true, "st_applicable_by_catalog": false,
    "icms": {"group": "ICMSSN102", "origin": "0", "csosn": "102", "situation_code": "102",
             "situation_field": "csosn", "taxation_kind": "simples_without_credit", "highlights_icms": false},
    "pis": {"group": "PISOutr", "cst": "49", "taxation_kind": "other"},
    "cofins": {"group": "COFINSOutr", "cst": "49", "taxation_kind": "other"},
    "ibs_cbs": {"present": true, "cst": "000", "class_code": "000001", "base_amount": "1000.00",
                "cbs": {"rate": "0.90", "effective_rate": "0.90", "amount": "9.00", "expected_amount": "9.00"},
                "ibs": {"amount": "1.00"},
                "schedule_rates": {"cbs": "0.90", "ibs_uf": "0.10", "ibs_city": "0.00"}}
  }]
}
```

Neste exemplo nenhuma regra de CSOSN dispara: devolução de venda emitida pelo próprio optante **espelha** a nota original (mesmo CSOSN 102, sem destaque) — quem confere isso é `DOC.RETURN.MIRROR`, e o 900 seria devolução de *compra* (ver `RULES_REVIEW.md`). A regra de referência de devolução (`DOC.RETURN.REFERENCE`) também passa, porque `references[0].resolved = true`.
