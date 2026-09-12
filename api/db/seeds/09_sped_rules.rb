load Rails.root.join("db/seeds/00_helpers.rb") unless respond_to?(:seed_rule!, true)
# Fase 2 — cross-check EFD ICMS/IPI × XML (PROJECT_SCOPE §4): transforma "erro no registro" em "erro causado pela nota X, item Y".
old = Date.new(2012, 1, 1)

# Tabelas do Guia Prático EFD ICMS/IPI que a primitiva compara (dado, não código):
# COD_MOD aceitos no C100 pela NF-e/NFC-e de emissão própria, IND_EMIT de emissão própria e COD_SIT por situação.
guia_models = %w[55 65]
guia_ind_emit_own = "0"                                # 0 = emissão própria
guia_cod_sit_cancelled = %w[02 03]                     # 02 cancelado, 03 cancelado extemporâneo
guia_cod_sit_regular = %w[00 01 06 07 08]              # regulares/extemporâneos, com direito a analítico C190
guia_cod_sit_values = %w[00 01]                        # só nesses os totais do C100 devem espelhar o XML
guia_tabela_412 = { "label" => "Guia Prático EFD ICMS/IPI, tabela 4.1.2 (COD_SIT)" }
ato_cotepe_44 = { "label" => "Ato COTEPE/ICMS 44/2018 — leiaute da EFD ICMS/IPI" }

# `{{problem}}` diz QUAL dos dois diagnósticos ocorreu (a primitiva emite os dois no mesmo check "presence", e só o
# `not_in_xml` traz `line`). Separar em duas regras, com severidades próprias, depende de a primitiva aceitar um check
# por diagnóstico — enquanto isso a mensagem tem de discriminar, senão o contador não sabe o que aconteceu.
seed_rule!("SPED.DOC.MISSING_IN_FILE", title: "NF-e autorizada fora da EFD (ou C100 sem XML na base)", scope: "period", severity: "error", effective_from: old, tags: %w[sped cross_check],
  primitive: { "name" => "sped_document_reconciliation", "params" => { "check" => "presence", "models" => guia_models, "own_issue_ind_emit" => guia_ind_emit_own } },
  message: "Divergência {{problem}} — NF-e {{number}} (chave {{access_key}}): em 'missing_in_file', a nota foi autorizada no período e não tem C100 no arquivo; em 'not_in_xml', o C100 da linha {{line}} não tem XML correspondente na base do cliente.",
  explanation: "Toda NF-e de emissão própria autorizada no período deve estar escriturada no C100. Nota fora do arquivo (missing_in_file) = omissão de saída; C100 sem XML (not_in_xml) = possível digitação manual, nota de outra base ou XML não enviado.",
  legal_references: [{ "label" => "Guia Prático EFD-ICMS/IPI, registro C100" }, guia_tabela_412])

seed_rule!("SPED.DOC.CANCELLED_SIT", title: "Nota cancelada escriturada com situação errada (COD_SIT)", scope: "period", severity: "error", effective_from: old, tags: %w[sped cross_check],
  primitive: { "name" => "sped_document_reconciliation", "params" => { "check" => "cancelled", "models" => guia_models, "cancelled_cod_sit" => guia_cod_sit_cancelled } },
  # o esperado sai do mesmo dado que a primitiva compara (02 e 03), em vez de "02" escrito na mensagem
  params: { "cancelled_cod_sit" => guia_cod_sit_cancelled },
  message: "NF-e {{number}} (chave {{access_key}}): cancelada no XML, mas no arquivo está com COD_SIT {{cod_sit}} (esperado {{params.cancelled_cod_sit}} — documento cancelado ou cancelado extemporâneo).",
  explanation: "Cancelada deve constar no C100 com COD_SIT 02 (ou 03, cancelamento extemporâneo) e sem valores. Escriturar como regular infla débitos; omitir quebra a sequência.",
  legal_references: [{ "label" => "Guia Prático EFD-ICMS/IPI, tabela COD_SIT" }, guia_tabela_412])

seed_rule!("SPED.DOC.VALUES", title: "Totais do C100 divergem do XML", scope: "period", severity: "error", effective_from: old, tags: %w[sped cross_check],
  primitive: { "name" => "sped_document_reconciliation", "params" => { "check" => "values", "tolerance" => "0.01", "models" => guia_models, "values_cod_sit" => guia_cod_sit_values } },
  message: "NF-e {{number}} (linha {{line}}): {{field}} = {{file_value}} no arquivo, {{xml_value}} no XML.",
  explanation: "Os totais escriturados no C100 devem reproduzir os do XML autorizado. Divergência típica: desconto/frete tratados diferente na escrituração, ou nota alterada após a emissão.",
  legal_references: [{ "label" => "Guia Prático EFD-ICMS/IPI, registro C100" }, guia_tabela_412],
  group_by: ["field"])

seed_rule!("SPED.ITEM.MISMATCH", title: "Item do C170 diverge do item do XML", scope: "period", severity: "error", effective_from: old, tags: %w[sped cross_check],
  primitive: { "name" => "sped_item_reconciliation", "params" => { "tolerance" => "0.02" } },
  message: "NF-e {{number}}, item {{item}} (linha {{line}}): {{field}} = {{file_value}} no arquivo, {{xml_value}} no XML.",
  explanation: "O C170 espelha o item do documento (CFOP, CST com origem, base, alíquota e valor de ICMS). Divergência aqui é a causa clássica de 'erro no registro 54/C170' do validador oficial.",
  legal_references: [{ "label" => "Guia Prático EFD-ICMS/IPI, registro C170" }, ato_cotepe_44],
  group_by: ["field"])

seed_rule!("SPED.C190.CONSISTENCY", title: "Registro analítico C190 não consolida os itens", scope: "period", severity: "error", effective_from: old, tags: %w[sped cross_check],
  primitive: { "name" => "sped_c190_consistency", "params" => { "tolerance" => "0.05" } },
  message: "C190 da linha {{line}} (CST {{cst}}, CFOP {{cfop}}, alíq. {{aliq}}%) não confere com os itens: {{field}} = {{file_value}} no analítico, {{expected_value}} na soma dos C170.",
  explanation: "O C190 é o somatório dos C170 por CST × CFOP × alíquota. Quando não bate, o PVA rejeita sem apontar a nota; aqui a linha e a chave de origem ficam identificadas. Campos vazios (—) na mensagem significam que nenhum C170 do documento tem essa combinação de CST × CFOP × alíquota.",
  legal_references: [{ "label" => "Guia Prático EFD-ICMS/IPI, registro C190" }, ato_cotepe_44])

seed_rule!("SPED.STRUCTURE", title: "Erros estruturais do arquivo (leiaute)", scope: "period", severity: "warning", effective_from: old, tags: %w[sped structure],
  primitive: { "name" => "sped_structure", "params" => {} },
  message: "Linha {{line}} ({{record}}): {{error}}.",
  explanation: "Erro de leiaute detectado na leitura do arquivo (registro fora da hierarquia, campo obrigatório vazio, número de campos diferente do leiaute, CNPJ do 0000 diferente do cliente). O PVA recusa o arquivo inteiro; aqui o problema fica localizado por linha e registro.",
  legal_references: [ato_cotepe_44, { "label" => "Guia Prático EFD-ICMS/IPI, item 2 (estrutura do arquivo)" }])

seed_rule!("SPED.DOC.NO_ANALYTIC", title: "C100 regular sem registro analítico C190", scope: "period", severity: "error", effective_from: Date.new(2012, 1, 1), tags: %w[sped cross_check],
  primitive: { "name" => "sped_document_reconciliation", "params" => { "check" => "analytic", "models" => guia_models, "own_issue_ind_emit" => guia_ind_emit_own, "analytic_cod_sit" => guia_cod_sit_regular } },
  message: "C100 nº {{number}} (linha {{line}}) sem nenhum C190: o registro analítico é obrigatório para todo documento regular (o C170 é dispensável na NF-e de emissão própria, o C190 não).",
  legal_references: [{ "label" => "Guia Prático EFD-ICMS/IPI, registro C100 (exceções 1 a 4)" }, guia_tabela_412])

puts "rules (sped): #{Rules::Rule.where("code LIKE 'SPED.%'").count}"
