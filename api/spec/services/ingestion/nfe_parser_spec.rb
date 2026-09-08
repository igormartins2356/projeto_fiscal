require "rails_helper"

RSpec.describe Ingestion::Nfe::Parser do
  subject(:doc) { described_class.call(nfe_fixture("sale_return_csosn_102")) }

  it "maps the canonical document" do
    expect(doc["kind"]).to eq("nfe")
    expect(doc["access_key"]).to eq("35260312345678000190550010000012341000012345")
    expect(doc["issuance"]).to include("number" => 1234, "series" => "1", "purpose" => "return")
    expect(doc["operation"]).to include("direction_declared" => "inbound", "scope" => "intrastate", "final_consumer" => false)
    expect(doc["issuer"]).to include("cnpj" => "12345678000190", "crt" => "1", "uf" => "SP")
    expect(doc["recipient"]).to include("ie_indicator" => "taxpayer")
    expect(doc["references"].first).to include("kind" => "nfe", "access_key" => "35260312345678000190550010000009991000009999")
    expect(doc["totals"]).to include("products" => "1000.00", "total" => "1000.00")
    expect(doc["protocol"]).to include("status_code" => "100")
    expect(doc["layout_groups"]).to include("ibs_cbs", "payment")
  end

  it "maps items and taxes, keeping absence as absence" do
    item = doc["items"].first
    expect(item["product"]).to include("code" => "A1", "ncm" => "84713012", "cfop" => "1202", "no_gtin" => true, "gross_amount" => "1000.00")
    expect(item["product"]).not_to have_key("gtin")
    expect(item["icms"]).to include("group" => "ICMSSN102", "csosn" => "102", "origin" => "0")
    expect(item["icms"]).not_to have_key("cst")
    expect(item["pis"]).to include("cst" => "49")
    expect(item["ibs_cbs"]).to include("present" => true, "cst" => "000", "class_code" => "000001", "base_amount" => "1000.00")
    expect(item["ibs_cbs"]["cbs"]).to include("rate" => "0.90", "amount" => "9.00")
  end
end
