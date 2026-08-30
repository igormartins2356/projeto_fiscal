require "rails_helper"

RSpec.describe "cross-document primitives & catalog importers" do
  before { seed_all! }
  let(:client) { Accounts::Client.find_by!(cnpj: "12345678000190") }

  def nfe(number:, series: "1", key_suffix:, purpose: "1", refs: [], qty: "2.0000", issued: "2026-03-14T10:22:00-03:00")
    xml = nfe_fixture("sale_return_csosn_102")
    xml = xml.sub("<nNF>1234</nNF>", "<nNF>#{number}</nNF>").sub("<serie>1</serie>", "<serie>#{series}</serie>").sub("<finNFe>4</finNFe>", "<finNFe>#{purpose}</finNFe>")
             .gsub("35260312345678000190550010000012341000012345", "35260312345678000190550010000#{key_suffix}").sub("<qCom>2.0000</qCom>", "<qCom>#{qty}</qCom>")
             .sub("<dhEmi>2026-03-14T10:22:00-03:00</dhEmi>", "<dhEmi>#{issued}</dhEmi>")
    xml = xml.sub(%r{<NFref>.*?</NFref>}m, refs.map { |r| "<NFref><refNFe>#{r}</refNFe></NFref>" }.join)
    xml = xml.sub("<CFOP>1202</CFOP>", "<CFOP>5102</CFOP>").sub("<tpNF>0</tpNF>", "<tpNF>1</tpNF>") if purpose == "1"
    Ingestion::DocumentImporter.new(client:).call(xml).document
  end

  it "detects numbering gaps, resolves references and flags returns exceeding the original" do
    original = nfe(number: 100, key_suffix: "01001000000101", purpose: "1", qty: "2.0000")
    nfe(number: 101, key_suffix: "01011000000102", purpose: "1")
    nfe(number: 105, key_suffix: "01051000000105", purpose: "1")   # lacuna 102..104
    ret = nfe(number: 106, key_suffix: "01061000000106", purpose: "4", refs: [original.access_key], qty: "3.0000")
    expect(ret.reload.data["references"].first).to include("resolved" => true, "document_id" => original.id)

    run = client.audit_runs.create!(firm_id: client.firm_id, period_start: Date.new(2026, 3, 1), period_end: Date.new(2026, 3, 31))
    Audit::Runner.new(run).call
    expect(run.reload.evaluation_errors.reject { |e| e["error"].include?("sem versão publicada") }).to eq([])
    gap = run.findings.find_by(rule_code: "DOC.NUMBERING.GAP")
    expect(gap.evidence).to include("missing_from" => 102, "missing_to" => 104, "missing_count" => 3)
    exceed = run.findings.find_by(rule_code: "DOC.RETURN.ORIGINAL")
    expect(exceed.evidence).to include("product_code" => "A1", "returned_quantity" => "3.0", "original_quantity" => "2.0")
    expect(run.findings.where(rule_code: "DOC.DUPLICATE.NUMBER_SERIES")).to be_empty
  end

  it "imports NCM json and cClassTrib json into draft versions" do
    r = Catalog::Importers::Ncm.new.call(json: { "Data_Ultima_Atualizacao" => "01/08/2026", "Nomenclaturas" => [
      { "Codigo" => "8471.30.12", "Descricao" => "Máquinas portáteis", "Data_Inicio" => "01/04/2022", "Data_Fim" => "31/12/9999" },
      { "Codigo" => "84.71", "Descricao" => "posição (ignorada)" },
      { "Codigo" => "0101.21.00", "Descricao" => "Cavalos", "Data_Inicio" => "01/04/2022", "Data_Fim" => "30/06/2025" }] })
    expect(r[:imported]).to eq(2)
    r[:version].update!(state: "published")
    expect(Catalog::Lookup.new(date: Date.new(2026, 3, 1)).lookup("ncm", ["84713012"])["description"]).to eq("Máquinas portáteis")
    expect(Catalog::Lookup.new(date: Date.new(2026, 3, 1)).lookup("ncm", ["01012100"])).to be_nil

    r2 = Catalog::Importers::IbsCbsClass.new.call(json: [{ "cClassTrib" => "000001", "CST" => "000", "Descricao" => "Tributação integral", "pRedAliq" => "0" }, { "cClassTrib" => "200003", "CST" => "200", "Descricao" => "Redução 60%", "pRedAliq" => "60" }])
    expect(r2[:imported]).to eq(2)
    r2[:version].update!(state: "published")
    expect(Catalog::Lookup.new(date: Date.current).lookup("ibs_cbs_class", ["200003"])).to include("cst" => "200", "reduction_pct" => "60")
  end
end
