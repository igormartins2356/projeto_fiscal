require "rails_helper"
require Rails.root.join("lib/rule_case_builder")

RSpec.describe Ingestion::Nfe::Derivations do
  # catálogo sem nenhuma versão publicada vigente na data
  let(:no_tables) { Class.new { def lookup(*) = nil; def table_available?(*) = false; def versions_used = {} }.new }
  # tabelas publicadas, mas sem a linha procurada (código inexistente)
  let(:empty_tables) { Class.new { def lookup(*) = nil; def table_available?(*) = true; def versions_used = {} }.new }

  it "usa a data local do dhEmi, sem converter para o fuso da aplicação" do
    doc = RuleCaseBuilder.doc(doc: { "issuance" => { "issued_at" => "2026-03-31T23:30:00-04:00" } })
    described_class.call(doc, monitored_cnpj: "12345678000190", catalog: no_tables)
    expect(doc["reference_date"]).to eq("2026-03-31")
    expect(doc["period"]).to eq("2026-03")
  end

  it "recusa documento sem dhEmi em vez de datar em Date.current" do
    doc = RuleCaseBuilder.doc(doc: { "issuance" => { "issued_at" => nil } })
    expect { described_class.call(doc, monitored_cnpj: "12345678000190", catalog: no_tables) }
      .to raise_error(Ingestion::Nfe::Parser::InvalidXml, /dhEmi ausente ou inválido/)
  end

  it "não grava derivado de catálogo quando a tabela não tem versão vigente" do
    doc = RuleCaseBuilder.doc(normal: true, item: { "ipi" => { "cst" => "50", "base_amount" => "1000.00", "rate" => "5.00", "amount" => "50.00" } })
    described_class.call(doc, monitored_cnpj: "12345678000190", catalog: no_tables)
    it_ = doc["items"].first
    expect(it_).not_to have_key("cfop_known")
    expect(it_).not_to have_key("cfop_nature")
    expect(it_).not_to have_key("cfop_st_role")
    expect(it_).not_to have_key("cfop_requires_reference")
    expect(it_).not_to have_key("cfop_own_production")
    expect(it_["icms"]).not_to have_key("taxation_kind")
    expect(it_["pis"]).not_to have_key("taxation_kind")
    expect(it_["pis"]).not_to have_key("cst_direction")
    expect(it_["ipi"]).not_to have_key("cst_direction")
  end

  it "mantém 'unknown' quando a tabela está publicada e o código não existe nela" do
    doc = RuleCaseBuilder.doc(normal: true)
    described_class.call(doc, monitored_cnpj: "12345678000190", catalog: empty_tables)
    it_ = doc["items"].first
    expect(it_).to include("cfop_known" => false, "cfop_nature" => "unknown", "cfop_st_role" => "unknown")
    expect(it_).not_to have_key("cfop_requires_reference")
    expect(it_["icms"]["taxation_kind"]).to eq("unknown")
  end

  it "não grava chave com nil quando o dado não existe" do
    doc = RuleCaseBuilder.doc(doc: { "recipient" => { "uf" => nil, "address" => nil }, "operation" => { "scope" => "intrastate" } },
                              item: { "product" => { "cfop" => "X999" }, "icms" => { "csosn" => nil, "group" => "ICMS00" } })
    described_class.call(doc, monitored_cnpj: "12345678000190", catalog: no_tables)
    expect(doc["operation"]).not_to have_key("destination_uf")
    it_ = doc["items"].first
    expect(it_).not_to have_key("cfop_group")
    expect(it_).not_to have_key("cfop_scope")
    expect(it_["icms"]).not_to have_key("situation_code")
    expect(it_["icms"]["situation_field"]).to eq("absent")
  end

  it "preserva references[].resolved já resolvido (rederivação não desresolve)" do
    doc = RuleCaseBuilder.doc(doc: { "references" => [{ "kind" => "nfe", "access_key" => "3" * 44, "resolved" => true, "document_id" => 7 }] })
    described_class.call(doc, monitored_cnpj: "12345678000190", catalog: no_tables)
    expect(doc["references"].first).to include("resolved" => true, "document_id" => 7)
  end
end
