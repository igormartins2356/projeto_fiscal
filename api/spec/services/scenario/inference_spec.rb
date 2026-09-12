require "rails_helper"

# Inferência do cenário a partir dos campos derivados/catálogo do item (não de listas literais de CFOP/CST/alíquota).
RSpec.describe Scenario::Inference do
  let(:firm) { Accounts::Firm.create!(name: "Firma") }
  let(:client) { Accounts::Client.create!(firm:, cnpj: "12345678000190", legal_name: "Cliente", uf: "SP") }
  let(:reference_date) { Date.new(2026, 8, 10) }

  def add_doc(items, crt: "3")
    doc = client.documents.create!(firm:, kind: "nfe", model: "55", xml_hash: SecureRandom.hex(32), xml_ref: "mem", role: "issuer", status_state: "authorized",
                                   reference_date:, data: { "issuer" => { "crt" => crt, "ie" => "123456789" }, "operation" => {}, "recipient" => {} })
    items.each_with_index { |it, idx| doc.items.create!(client:, number: idx + 1, data: it) }
    doc
  end

  # Item de regime normal: PIS CST 01 tributado; ICMS 00; sem ST; CFOP conforme catálogo
  def item(cfop: "5102", own_production: false, st_role: "none", nature: "sale", icms_kind: "taxed", pis_kind: "taxed", pis_rate: "0.65", pis_direction: "outbound")
    { "product" => { "cfop" => cfop }, "cfop_nature" => nature, "cfop_own_production" => own_production, "cfop_st_role" => st_role,
      "icms" => { "taxation_kind" => icms_kind }, "pis" => { "taxation_kind" => pis_kind, "cst_direction" => pis_direction, "rate" => pis_rate } }
  end

  # Regra publicada de onde a inferência lê as alíquotas-limite (mesma estrutura da seed 04_rules_extra.rb)
  def publish_rate_rule!
    Rules::Rule.create!(code: "PISCOFINS.RATE.REGIME", version: 1, title: "PIS/COFINS × regime", scope: "item", severity: "error", state: "published",
                        effective_from: Date.new(2010, 1, 1), effective_until: Date.new(2026, 12, 31),
                        body: { "assert" => { "if" => { "field" => "scenario.pis_cofins.regime", "op" => "eq", "value" => "non_cumulative" },
                                              "then" => { "all" => [{ "field" => "item.pis.rate", "op" => "approx", "value" => "1.65", "tolerance" => "0.001" }] },
                                              "else" => { "all" => [{ "field" => "item.pis.rate", "op" => "approx", "value" => "0.65", "tolerance" => "0.001" }] } } })
  end

  def infer = described_class.new(client, months: 12).call[:fields]

  it "conta CFOP de produção própria fora da lista antiga (5104) como indústria via cfop_own_production" do
    publish_rate_rule!
    add_doc([item(cfop: "5104", own_production: true), item(cfop: "5104", own_production: true), item(cfop: "6108")])
    activity = infer["activity"]
    expect(activity["value"]).to include("industry")
    expect(activity["evidence"]).to include("produção própria (catálogo): 67%")
    expect(activity["confidence"]).to eq(0.95)
  end

  it "conta item com icms.taxation_kind st_withheld como ST" do
    publish_rate_rule!
    add_doc([item(cfop: "5405", st_role: "substituted", icms_kind: "st_withheld"), item])
    expect(infer["st"]["value"]["applies"]).to be true
  end

  it "não aponta ST quando não há retenção nem destaque" do
    publish_rate_rule!
    add_doc([item, item])
    expect(infer["st"]["value"]["applies"]).to be false
  end

  it "lê da regra publicada a alíquota que separa não cumulativo (1,65) de cumulativo (0,65)" do
    publish_rate_rule!
    add_doc([item(pis_rate: "1.65"), item(pis_rate: "1.65")])
    f = infer
    expect(f["pis_cofins"]["value"]).to eq({ "regime" => "non_cumulative" })
    expect(f["tax_regime"]["value"]).to eq("lucro_real")

    client.documents.destroy_all
    add_doc([item(pis_rate: "0.65"), item(pis_rate: "0.65")])
    f = infer
    expect(f["pis_cofins"]["value"]).to eq({ "regime" => "cumulative" })
    expect(f["tax_regime"]["value"]).to eq("lucro_presumido")
  end

  it "não chuta o regime quando a regra de alíquotas não tem versão vigente" do
    add_doc([item(pis_rate: "1.65"), item(pis_rate: "1.65")])
    pc = infer["pis_cofins"]
    expect(pc["value"]).to eq({})
    expect(pc["confidence"]).to eq(0.0)
    expect(pc["evidence"]).to include("sem versão publicada vigente")
  end

  it "ignora regra de mesmo code publicada por outra firma (isolamento entre escritórios)" do
    publish_rate_rule!
    other_firm = Accounts::Firm.create!(name: "Outro escritório")
    Rules::Rule.create!(code: "PISCOFINS.RATE.REGIME", version: 2, title: "PIS/COFINS × regime (outra firma)", scope: "item", severity: "error",
                        state: "published", source_type: "firm", source_id: other_firm.id,
                        effective_from: Date.new(2010, 1, 1), effective_until: Date.new(2026, 12, 31),
                        body: { "assert" => { "if" => { "field" => "scenario.pis_cofins.regime", "op" => "eq", "value" => "non_cumulative" },
                                              "then" => { "all" => [{ "field" => "item.pis.rate", "op" => "approx", "value" => "0.65", "tolerance" => "0.001" }] },
                                              "else" => { "all" => [{ "field" => "item.pis.rate", "op" => "approx", "value" => "1.65", "tolerance" => "0.001" }] } } })
    add_doc([item(pis_rate: "1.65"), item(pis_rate: "1.65")])
    expect(infer["pis_cofins"]["value"]).to eq({ "regime" => "non_cumulative" })
  end

  it "infere Simples pelo taxation_kind 'other' do CST de PIS" do
    add_doc([item(pis_kind: "other", pis_rate: "0"), item(pis_kind: "other", pis_rate: "0")], crt: "1")
    f = infer
    expect(f["pis_cofins"]["value"]).to eq({ "regime" => "simples" })
    expect(f["tax_regime"]["value"]).to eq("simples_nacional")
  end
end
