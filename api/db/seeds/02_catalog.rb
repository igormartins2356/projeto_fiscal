load Rails.root.join("db/seeds/00_helpers.rb") unless respond_to?(:seed_table!, true)

# CFOP — recorte; a tabela completa vem do importador (DATA_SOURCES.md §1.3). Colunas nature/direction/st_role/requires_reference/own_production são curadoria nossa.
cfop = {
  "1101" => "purchase", "1102" => "purchase", "1111" => "purchase", "1113" => "purchase", "1116" => "purchase", "1117" => "purchase",
  "1201" => "sale_return", "1202" => "sale_return", "1203" => "sale_return", "1204" => "sale_return", "1410" => "sale_return", "1411" => "sale_return",
  "1152" => "transfer", "1403" => "purchase", "1949" => "other",
  "2101" => "purchase", "2102" => "purchase", "2201" => "sale_return", "2202" => "sale_return", "2403" => "purchase", "2410" => "sale_return", "2411" => "sale_return", "2949" => "other",
  "3101" => "import", "3102" => "import",
  "5101" => "sale", "5102" => "sale", "5103" => "sale", "5104" => "sale", "5105" => "sale", "5106" => "sale", "5109" => "sale", "5110" => "sale", "5111" => "sale", "5112" => "sale",
  "5401" => "sale", "5403" => "sale", "5405" => "sale", "5152" => "transfer", "5201" => "purchase_return", "5202" => "purchase_return", "5410" => "purchase_return", "5411" => "purchase_return",
  "5910" => "bonus", "5911" => "bonus", "5912" => "demonstration", "5913" => "shipment_return", "5915" => "shipment", "5916" => "shipment_return", "5917" => "consignment", "5918" => "shipment_return", "5949" => "other",
  "6101" => "sale", "6102" => "sale", "6107" => "sale", "6108" => "sale", "6401" => "sale", "6403" => "sale", "6404" => "sale", "6152" => "transfer", "6201" => "purchase_return", "6202" => "purchase_return", "6410" => "purchase_return", "6411" => "purchase_return", "6910" => "bonus", "6949" => "other",
  "7101" => "export", "7102" => "export"
}
# Complementos exigidos pela base completa de regras, compostos ANTES de publicar a v1 (linha de versão publicada não se edita — findings e snapshots apontam para ela).
cfop = { "5405" => "sale", "6404" => "sale", "5402" => "sale", "6402" => "sale", "5656" => "sale", "6656" => "sale", "1653" => "purchase", "2653" => "purchase",
         "5117" => "sale", "6117" => "sale", "5118" => "sale", "5119" => "sale", "5120" => "sale", "5122" => "sale", "5123" => "sale", "5124" => "industrialization", "5125" => "industrialization",
         "5901" => "shipment", "5902" => "shipment_return", "5903" => "shipment_return", "5904" => "shipment", "5905" => "shipment", "5906" => "shipment_return", "5907" => "shipment_return", "5908" => "shipment", "5909" => "shipment_return",
         "5920" => "shipment", "5921" => "shipment", "5922" => "other", "5923" => "shipment", "5924" => "shipment", "5925" => "shipment_return", "5926" => "other", "5927" => "other", "5928" => "other", "5929" => "other",
         "6901" => "shipment", "6902" => "shipment_return", "6905" => "shipment", "6906" => "shipment_return", "6910" => "bonus", "6911" => "bonus", "6912" => "demonstration", "6913" => "shipment_return", "6915" => "shipment", "6916" => "shipment_return", "6917" => "consignment", "6918" => "shipment_return", "6920" => "shipment", "6949" => "other",
         "1901" => "shipment_return", "1902" => "shipment_return", "1903" => "shipment", "1904" => "shipment", "1905" => "shipment", "1906" => "shipment", "1908" => "shipment", "1909" => "shipment", "1910" => "bonus", "1911" => "bonus", "1912" => "demonstration", "1913" => "shipment_return", "1915" => "shipment", "1916" => "shipment_return", "1917" => "consignment", "1918" => "shipment_return", "1949" => "other",
         "2901" => "shipment_return", "2902" => "shipment_return", "2910" => "bonus", "2911" => "bonus", "2912" => "demonstration", "2913" => "shipment_return", "2915" => "shipment", "2916" => "shipment_return", "2949" => "other",
         "1124" => "industrialization", "1125" => "industrialization", "2124" => "industrialization", "2125" => "industrialization", "1126" => "purchase", "1401" => "purchase", "2401" => "purchase",
         "5501" => "sale", "5502" => "sale", "6501" => "sale", "6502" => "sale", "7101" => "export", "7102" => "export", "7127" => "export", "7949" => "other", "3101" => "import", "3102" => "import", "3949" => "other" }.merge(cfop)
# Famílias inteiras do Anexo que faltavam (curadoria 09/09/2026): apontar "CFOP inexistente" num código legítimo custa a
# confiança do contador, então o recorte foi ampliado por sufixo, expandindo para as saídas (5/6) e as entradas (1/2).
# Onde a natureza não é evidente (serviços 3xx, transporte 35x, energia 25x, combustíveis 65x, crédito/ressarcimento 60x)
# fica "other": nenhuma regra de CFOP julga essas naturezas, e inventar curadoria seria pior que não ter.
out_extra = { "113" => "sale", "114" => "sale", "115" => "sale", "116" => "sale", "151" => "transfer", "153" => "transfer", "155" => "transfer", "156" => "transfer",
              # 205/206/207/213 são ANULAÇÃO DE VALOR (comunicação, transporte, energia, ressarcimento de ICMS-ST), não devolução:
              # saem com finNFe 1/2/3 e viravam falso positivo em CFOP.RETURN.PURPOSE (error) quando classificados como devolução.
              "205" => "other", "206" => "other", "207" => "other", "208" => "purchase_return", "209" => "purchase_return", "210" => "purchase_return", "213" => "other",
              "251" => "sale", "252" => "sale", "253" => "sale", "254" => "sale", "255" => "sale", "256" => "sale", "257" => "sale", "258" => "sale",
              "301" => "other", "302" => "other", "303" => "other", "304" => "other", "305" => "other", "306" => "other", "307" => "other",
              "351" => "other", "352" => "other", "353" => "other", "354" => "other", "355" => "other", "356" => "other", "357" => "other", "359" => "other", "360" => "other",
              # família 5.408-5.415 / 6.408-6.415 (operações com mercadoria sujeita a ST que não são venda): 408/409 transferência,
              # 410-413 devolução de compra, 414/415 remessa para venda fora do estabelecimento. O papel na ST vai em st_roles.
              "408" => "transfer", "409" => "transfer", "410" => "purchase_return", "411" => "purchase_return", "412" => "purchase_return", "413" => "purchase_return", "414" => "shipment", "415" => "shipment",
              "503" => "purchase_return", "504" => "shipment", "505" => "shipment",
              "551" => "sale", "552" => "transfer", "553" => "purchase_return", "554" => "shipment", "555" => "shipment_return", "556" => "purchase_return", "557" => "transfer",
              "601" => "other", "602" => "other", "603" => "other", "605" => "other", "606" => "other",
              "651" => "sale", "652" => "sale", "653" => "sale", "654" => "sale", "655" => "sale", "657" => "sale", "658" => "sale", "659" => "other", "660" => "other", "661" => "other", "662" => "other", "663" => "other", "664" => "other", "665" => "other", "666" => "other", "667" => "other",
              "914" => "shipment", "919" => "shipment_return", "930" => "other", "931" => "other", "932" => "other", "933" => "other", "934" => "shipment" }
in_extra = { "118" => "purchase", "120" => "purchase", "121" => "purchase", "122" => "purchase", "128" => "purchase", "135" => "purchase",
             "151" => "transfer", "152" => "transfer", "153" => "transfer", "154" => "transfer", "155" => "transfer", "156" => "transfer",
             "203" => "sale_return", "204" => "sale_return", "205" => "other", "206" => "other", "207" => "other", "208" => "sale_return", "209" => "sale_return", "210" => "sale_return", "212" => "sale_return", "213" => "other",
             "251" => "purchase", "252" => "purchase", "253" => "purchase", "254" => "purchase", "255" => "purchase", "256" => "purchase", "257" => "purchase", "258" => "purchase",
             "301" => "other", "302" => "other", "303" => "other", "304" => "other", "305" => "other", "306" => "other",
             "351" => "other", "352" => "other", "353" => "other", "354" => "other", "355" => "other", "356" => "other", "360" => "other",
             "406" => "purchase", "407" => "purchase", "408" => "transfer", "409" => "transfer", "414" => "shipment_return", "415" => "shipment_return",
             "503" => "sale_return", "504" => "shipment_return", "505" => "shipment_return",
             "551" => "purchase", "552" => "transfer", "553" => "sale_return", "554" => "shipment_return", "555" => "shipment", "556" => "purchase", "557" => "transfer",
             "601" => "other", "602" => "other", "603" => "other", "604" => "other", "605" => "other",
             "651" => "purchase", "652" => "purchase", "653" => "purchase", "658" => "purchase", "659" => "other", "660" => "other", "661" => "other", "662" => "other", "663" => "other", "664" => "other", "665" => "other", "666" => "other",
             "914" => "shipment_return", "919" => "shipment", "931" => "other", "932" => "other", "933" => "other", "934" => "shipment_return" }
extra = {}
out_extra.each { |suffix, n| %w[5 6].each { |pre| extra["#{pre}#{suffix}"] = n } }
in_extra.each { |suffix, n| %w[1 2].each { |pre| extra["#{pre}#{suffix}"] = n } }
# ZFM/ALC e exportação
extra.merge!("6109" => "sale", "6110" => "sale", "6111" => "sale", "6112" => "sale", "6113" => "sale", "6114" => "sale", "6115" => "sale", "6116" => "sale",
             "3126" => "import", "3127" => "import", "3128" => "import", "3201" => "purchase_return", "3202" => "purchase_return", "3205" => "purchase_return", "3211" => "purchase_return", "3251" => "purchase", "3352" => "other", "3551" => "purchase", "3553" => "sale_return", "3556" => "purchase", "3651" => "purchase", "3652" => "purchase", "3653" => "purchase", "3930" => "other",
             "7105" => "export", "7106" => "export", "7201" => "purchase_return", "7202" => "purchase_return", "7205" => "purchase_return", "7211" => "purchase_return", "7251" => "export", "7301" => "other", "7358" => "other", "7501" => "export", "7504" => "export", "7551" => "export", "7553" => "purchase_return", "7556" => "purchase_return", "7651" => "export", "7654" => "export", "7667" => "export", "7930" => "other", "7949" => "other")
cfop = extra.merge(cfop) # o recorte curado acima vence sobre os complementos

# Papel na ST (substitute = vende com ST retendo; substituted = mercadoria com ST já retida; none), se exige nota referenciada e se é produção própria
# `st_other` = operação com mercadoria sujeita a ST em que o CST correto depende do caso concreto e nenhuma regra de ST julga:
# venda entre contribuintes substitutos do MESMO produto (5.402/6.402) e transferência/remessa para venda fora do estabelecimento
# (5.408/5.409/5.414/5.415), hipóteses em que o Convênio ICMS 142/2018 (cláusula nona, I e II) dispensa a retenção — sai CST 00,
# e não 10/30/70/90. Marcá-las como `substitute`/`none` gerava falso positivo em error (CFOP.ST.SUBSTITUTE_CST / CFOP.ST.NONE_WITH_ST_CST).
st_roles = { "substitute" => %w[5401 5403 6401 6403 5410 5411 5412 5413 6410 6411 6412 6413 1401 1403 2401 2403 1410 1411 2410 2411],
             "substituted" => %w[5405 6404 5656 6656 1653 2653],
             "st_other" => %w[5402 6402 5408 6408 5409 6409 5414 6414 5415 6415] }
requires_reference = %w[1201 1202 1203 1204 1410 1411 2201 2202 2410 2411 5201 5202 5410 5411 6201 6202 6410 6411]
own_production = %w[5101 6101 7101 5401 6401 5501 6501 5124 5125]
# Vigência a partir de 01/01/2003 (Ajuste SINIEF 07/2001 reestruturou os CFOPs): antes disso o lookup fica indisponível
# e os derivados de CFOP ficam ausentes. A lista é a vigente hoje — códigos criados depois de 2003 são aceitos
# retroativamente (falso negativo tolerado; o contrário apontaria "CFOP inexistente" em código legítimo).
seed_table!("cfop", name: "CFOP", key_names: ["cfop"], source_class: "B", effective_from: Date.new(2003, 1, 1),
            source_url: "https://www.confaz.fazenda.gov.br/legislacao/ajustes/sinief/cfop_cvsn_70_vigente", legal_basis: "Ajuste SINIEF s/nº 1970, Anexo (Ajuste SINIEF 03/24)",
            rows: cfop.map { |c, n|
              role = st_roles.find { |_, codes| codes.include?(c) }&.first || "none"
              [[c], { "nature" => n, "direction" => c.start_with?("1", "2", "3") ? "inbound" : "outbound", "st_related" => role != "none", "st_role" => role,
                      "requires_reference" => requires_reference.include?(c), "own_production" => own_production.include?(c) }]
            })

csosn = { "101" => "simples_with_credit", "102" => "simples_without_credit", "103" => "exempt", "201" => "simples_with_credit_st", "202" => "simples_without_credit_st",
          "203" => "exempt_st", "300" => "immune", "400" => "not_taxed", "500" => "st_withheld", "900" => "other" }
seed_table!("csosn", name: "CSOSN", key_names: ["csosn"], source_class: "D", effective_from: Date.new(2010, 1, 1), legal_basis: "Ajuste SINIEF 07/05, Tabela B",
            rows: csosn.map { |c, k| [[c], { "taxation_kind" => k, "regime" => "simples_nacional" }] })

cst_icms = { "00" => "taxed", "10" => "taxed_with_st", "20" => "reduced_base", "30" => "exempt_with_st", "40" => "exempt", "41" => "not_taxed", "50" => "suspended",
             "51" => "deferred", "60" => "st_withheld", "70" => "reduced_base_with_st", "90" => "other" }
seed_table!("cst_icms", name: "CST ICMS", key_names: ["cst"], source_class: "D", effective_from: Date.new(2000, 1, 1), legal_basis: "Ajuste SINIEF 07/05, Tabela B",
            rows: cst_icms.map { |c, k| [[c], { "taxation_kind" => k, "regime" => "normal" }] })

cst_pc = { "01" => "taxed", "02" => "taxed", "03" => "taxed", "04" => "single_phase", "05" => "st", "06" => "zero_rate", "07" => "exempt", "08" => "no_incidence", "09" => "suspended",
           "49" => "other", "50" => "taxed", "51" => "taxed", "52" => "taxed", "53" => "taxed", "54" => "taxed", "55" => "taxed", "56" => "taxed",
           "60" => "taxed", "61" => "taxed", "62" => "taxed", "63" => "taxed", "64" => "taxed", "65" => "taxed", "66" => "taxed", "67" => "taxed",
           "70" => "other", "71" => "other", "72" => "other", "73" => "other", "74" => "other", "75" => "other", "98" => "other", "99" => "other" }
# direction: 01-49 saída, 50-99 entrada
seed_table!("cst_pis_cofins", name: "CST PIS/COFINS", key_names: ["cst"], source_class: "D", effective_from: Date.new(2000, 1, 1), legal_basis: "Tabela 4.3.3 SPED",
            rows: cst_pc.map { |c, k| [[c], { "taxation_kind" => k, "direction" => c.to_i <= 49 ? "outbound" : "inbound" }] })

# Cronograma IBS/CBS (DATA_SOURCES.md §1.11). 2027+ CBS é estimativa até a Resolução do Senado.
sched = [
  [["2026", "cbs"], { "rate" => "0.90", "kind" => "test" }], [["2026", "ibs_uf"], { "rate" => "0.10", "kind" => "test" }], [["2026", "ibs_city"], { "rate" => "0.00", "kind" => "test" }],
  [["2027", "cbs"], { "rate" => "9.21", "kind" => "estimated", "note" => "estimativa CGIBS 06/08/2026; aguardando Resolução do Senado" }],
  [["2027", "ibs_uf"], { "rate" => "0.05", "kind" => "test" }], [["2027", "ibs_city"], { "rate" => "0.05", "kind" => "test" }]
]
seed_table!("ibs_cbs_schedule", name: "Cronograma IBS/CBS", key_names: %w[year tax], source_class: "D", effective_from: Date.new(2026, 1, 1), legal_basis: "LC 214/2025 arts. 343-349", rows: sched)

# Alíquotas interestaduais (Res. Senado 22/89 e 13/2012): gerado a partir das regiões.
south_southeast = %w[SP RJ MG RS SC PR] # ES fica de fora (destino recebe 12%)
ufs = %w[AC AL AP AM BA CE DF ES GO MA MT MS MG PA PB PR PE PI RJ RN RS RO RR SC SP SE TO]
inter = []
ufs.each do |o|
  ufs.each do |d|
    next if o == d
    rate = south_southeast.include?(o) && !south_southeast.include?(d) ? "7.00" : "12.00"
    inter << [[o, d, "domestic"], { "rate" => rate }]
    inter << [[o, d, "imported"], { "rate" => "4.00" }]
  end
end
seed_table!("icms_interstate_rate", name: "Alíquota interestadual ICMS", key_names: %w[origin_uf destination_uf origin_category], source_class: "D", effective_from: Date.new(2013, 1, 1),
            legal_basis: "Resolução Senado 22/1989; Resolução Senado 13/2012", rows: inter)

# Alíquota interna geral por UF ("*" = geral) — recorte Sudeste; demais UFs entram na curadoria (DATA_SOURCES.md §1.6).
# fcp_rate geral: só RJ aplica FCP amplo (2%); MG/ES/SP têm FCP apenas em NCMs específicos (linhas por NCM)
internal = { "SP" => ["18.00", "0.00"], "MG" => ["18.00", "0.00"], "RJ" => ["20.00", "2.00"], "ES" => ["17.00", "0.00"] }
seed_table!("icms_internal_rate", name: "Alíquota interna ICMS", key_names: %w[uf ncm], source_class: "C", effective_from: Date.new(2024, 1, 1),
            legal_basis: "Lei estadual do ICMS de cada UF (verificar por linha)", rows: internal.map { |uf, (r, fcp)| [[uf, "*"], { "rate" => r, "fcp_rate" => fcp }] })
