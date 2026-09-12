load Rails.root.join("db/seeds/00_helpers.rb") unless respond_to?(:seed_table!, true) && respond_to?(:seed_rule!, true)
# Complementos de catálogo exigidos pela base completa de regras. Linha de versão publicada NÃO se edita aqui (findings e audit_runs.snapshot
# apontam para ela): o enriquecimento de cfop (CFOPs extras, st_role, requires_reference, own_production), cst_pis_cofins (direction) e
# icms_internal_rate (FCP MG = 0) foi para 02_catalog.rb, antes de publicar a v1. Banco semeado antes dessa mudança mantém o dado antigo — em dev, db:reset.

# CST IPI (Tabela 4.3.2 SPED): 00-49 entrada, 50-99 saída
cst_ipi = { "00" => %w[inbound taxed], "01" => %w[inbound taxed], "02" => %w[inbound exempt], "03" => %w[inbound exempt], "04" => %w[inbound immune], "05" => %w[inbound suspended],
            "49" => %w[inbound other], "50" => %w[outbound taxed], "51" => %w[outbound taxed], "52" => %w[outbound exempt], "53" => %w[outbound not_taxed], "54" => %w[outbound immune], "55" => %w[outbound suspended], "99" => %w[outbound other] }
seed_table!("cst_ipi", name: "CST IPI", key_names: ["cst"], source_class: "D", effective_from: Date.new(2000, 1, 1), legal_basis: "Tabela 4.3.2 SPED / IN RFB 1.009/2010",
            rows: cst_ipi.map { |c, (dir, kind)| [[c], { "direction" => dir, "taxation_kind" => kind }] })

# Cronograma IBS/CBS: alíquota-teste de IBS municipal em 2026 é 0 (o 0,1% é estadual). Já está no seed principal.

# Tabelas previstas em DATA_SOURCES.md ainda sem importação: registradas sem versão (lookup estrito vira evaluation_error até publicar).
[["tipi", "TIPI — alíquotas de IPI por NCM", ["ncm"], "B", "https://www.gov.br/receitafederal/pt-br/assuntos/orientacao-tributaria/ipi"],
 ["pis_cofins_special", "PIS/COFINS — NCM monofásicos, alíquota zero, suspensão", ["ncm"], "B", "https://www.gov.br/sped/pt-br"],
 ["ibs_cbs_class", "Classificação tributária IBS/CBS (cClassTrib)", ["class_code"], "A", "https://dfe-portal.svrs.rs.gov.br/DFE/ClassificacaoTributaria"],
 ["cest", "CEST por NCM (Convênio ICMS 142/18)", ["ncm"], "B", "https://www.confaz.fazenda.gov.br/legislacao/convenios/2018/CV142_18"],
 ["st_uf", "NCM/CEST sujeitos a ST por UF", %w[uf code], "C", nil],
 ["ncm", "NCM", ["ncm"], "A", "https://portalunico.siscomex.gov.br/classif/api/publico/nomenclatura/download/json?perfil=PUBLICO"]].each do |code, name, keys, klass, url|
  Catalog::ReferenceTable.find_or_create_by!(code:) { |t| t.name = name; t.key_names = keys; t.key_arity = keys.size; t.source_class = klass; t.source_url = url; t.next_review_on = Date.current }
end
puts "catalog: tabelas pendentes registradas"

# cadência de revisão por classe (DATA_SOURCES.md §3): A=sincronização automática; B=mensal; C=trimestral; D=anual
{"A" => 90, "B" => 30, "C" => 90, "D" => 365}.each do |klass, days|
  Catalog::ReferenceTable.where(source_class: klass).where(next_review_on: nil).update_all(next_review_on: Date.current + days)
end
