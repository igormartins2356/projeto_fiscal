load Rails.root.join("db/seeds/00_helpers.rb") unless respond_to?(:seed_rule!, true)
# Fase 2 — cross-check EFD ICMS/IPI × XML (PROJECT_SCOPE §4): transforma "erro no registro" em "erro causado pela nota X, item Y".
old = Date.new(2012, 1, 1)

seed_rule!("SPED.DOC.MISSING_IN_FILE", title: "NF-e autorizada fora da EFD", scope: "period", severity: "error", effective_from: old, tags: %w[sped cross_check],
  primitive: { "name" => "sped_document_reconciliation", "params" => { "check" => "presence" } },
  message: "{{problem}} — NF-e {{number}}/{{series}} (chave {{access_key}}) autorizada no período e ausente do arquivo (C100); ou registro C100 linha {{line}} sem XML correspondente na base.",
  explanation: "Toda NF-e de emissão própria autorizada no período deve estar escriturada no C100. Nota fora do arquivo = omissão de saída; C100 sem XML = possível digitação manual ou nota de outra base.",
  legal_references: [{ "label" => "Guia Prático EFD-ICMS/IPI, registro C100" }])

seed_rule!("SPED.DOC.CANCELLED_SIT", title: "Nota cancelada escriturada com situação errada (COD_SIT)", scope: "period", severity: "error", effective_from: old, tags: %w[sped cross_check],
  primitive: { "name" => "sped_document_reconciliation", "params" => { "check" => "cancelled" } },
  message: "NF-e {{number}} (chave {{access_key}}): cancelada no XML, mas no arquivo está com COD_SIT {{cod_sit}} (esperado 02 — documento cancelado).",
  explanation: "Cancelada deve constar no C100 com COD_SIT 02 e sem valores. Escriturar como regular infla débitos; omitir quebra a sequência.",
  legal_references: [{ "label" => "Guia Prático EFD-ICMS/IPI, tabela COD_SIT" }])

seed_rule!("SPED.DOC.VALUES", title: "Totais do C100 divergem do XML", scope: "period", severity: "error", effective_from: old, tags: %w[sped cross_check],
  primitive: { "name" => "sped_document_reconciliation", "params" => { "check" => "values", "tolerance" => "0.01" } },
  message: "NF-e {{number}} (linha {{line}}): {{field}} = {{file_value}} no arquivo, {{xml_value}} no XML.",
  explanation: "Os totais escriturados no C100 devem reproduzir os do XML autorizado. Divergência típica: desconto/frete tratados diferente na escrituração, ou nota alterada após a emissão.",
  group_by: ["field"])

seed_rule!("SPED.ITEM.MISMATCH", title: "Item do C170 diverge do item do XML", scope: "period", severity: "error", effective_from: old, tags: %w[sped cross_check],
  primitive: { "name" => "sped_item_reconciliation", "params" => { "tolerance" => "0.02" } },
  message: "NF-e {{number}}, item {{item}} (linha {{line}}): {{field}} = {{file_value}} no arquivo, {{xml_value}} no XML.",
  explanation: "O C170 espelha o item do documento (CFOP, CST com origem, base, alíquota e valor de ICMS). Divergência aqui é a causa clássica de 'erro no registro 54/C170' do validador oficial.",
  group_by: ["field"])

seed_rule!("SPED.C190.CONSISTENCY", title: "Registro analítico C190 não consolida os itens", scope: "period", severity: "error", effective_from: old, tags: %w[sped cross_check],
  primitive: { "name" => "sped_c190_consistency", "params" => { "tolerance" => "0.05" } },
  message: "C190 linha {{line}} (CST {{cst}}, CFOP {{cfop}}, alíq. {{aliq}}%): {{problem}} — {{field}} = {{file_value}}, soma dos C170 = {{expected_value}}.",
  explanation: "O C190 é o somatório dos C170 por CST × CFOP × alíquota. Quando não bate, o PVA rejeita sem apontar a nota; aqui a linha e a chave de origem ficam identificadas.")

seed_rule!("SPED.STRUCTURE", title: "Erros estruturais do arquivo (leiaute)", scope: "period", severity: "warning", effective_from: old, tags: %w[sped structure],
  primitive: { "name" => "sped_structure", "params" => {} },
  message: "Linha {{line}} ({{record}}): {{error}}.")

puts "rules (sped): #{Rules::Rule.where("code LIKE 'SPED.%'").count}"

seed_rule!("SPED.DOC.NO_ANALYTIC", title: "C100 regular sem registro analítico C190", scope: "period", severity: "error", effective_from: Date.new(2012, 1, 1), tags: %w[sped cross_check],
  primitive: { "name" => "sped_document_reconciliation", "params" => { "check" => "analytic" } },
  message: "C100 nº {{number}} (linha {{line}}) sem nenhum C190: o registro analítico é obrigatório para todo documento regular (o C170 é dispensável na NF-e de emissão própria, o C190 não).",
  legal_references: [{ "label" => "Guia Prático EFD-ICMS/IPI, registro C100 (exceções 1 a 4)" }])
