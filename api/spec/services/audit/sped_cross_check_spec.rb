require "rails_helper"
require Rails.root.join("lib/rule_case_builder")

RSpec.describe "cross-check SPED × XML (fase 2)" do
  before { seed_all! }
  let(:client) { Accounts::Client.find_by!(cnpj: "12345678000190") }

  def key_for(n) = "3526071234567800019055001000" + n.to_s.rjust(6, "0") + "1000" + n.to_s.rjust(6, "0")   # 44 chars

  def import_doc(number, cancelled: false)
    canonical = RuleCaseBuilder.doc(normal: true, doc: { "access_key" => key_for(number), "xml_hash" => SecureRandom.hex(32),
                                                         "issuance" => { "number" => number, "issued_at" => "2026-07-#{format('%02d', (number % 27) + 1)}T10:00:00-03:00" } })
    Ingestion::Nfe::Derivations.call(canonical, monitored_cnpj: client.cnpj)
    canonical["status"] = { "state" => "cancelled" } if cancelled
    items = canonical.delete("items")
    doc = Ingestion::Document.create!(firm_id: client.firm_id, client:, kind: "nfe", model: "55", access_key: canonical["access_key"], xml_hash: canonical["xml_hash"],
                                      xml_ref: "spec", layout_version: "4.00", role: "issuer", reference_date: canonical["reference_date"], period: canonical["period"],
                                      issued_at: canonical.dig("issuance", "issued_at"), series: "1", number:, issuer_cnpj: client.cnpj, direction: "outbound",
                                      operation_nature: canonical.dig("operation", "nature"), status_state: canonical.dig("status", "state"), total_amount: canonical.dig("totals", "total"), data: canonical)
    items.each { |i| Ingestion::DocumentItem.create!(document: doc, client:, number: i["number"], cfop: i.dig("product", "cfop"), ncm: i.dig("product", "ncm"), icms_situation_code: i.dig("icms", "situation_code"), net_amount: i["net_amount"], data: i) }
    doc
  end

  # Leiaute oficial (29 campos): ...|VL_MERC|IND_FRT|VL_FRT|VL_SEG|VL_OUT_DA|VL_BC_ICMS|VL_ICMS|...
  def c100_line(number, cod_sit: "00", vl_icms: "180,00", chv: key_for(number))
    "|C100|1|0|CLI001|55|#{cod_sit}|1|#{number}|#{chv}|10072026|10072026|1000,00|2|0,00|0,00|1000,00|9|0,00|0,00|0,00|1000,00|#{vl_icms}|0,00|0,00|0,00|6,50|30,00|0,00|0,00|"
  end

  # Leiaute oficial do C170 (38 campos)
  def c170_line(cfop: "5102", vl_icms: "180,00")
    "|C170|1|A1|Produto A|2,0000|UN|1000,00|0,00|0|000|#{cfop}|001|1000,00|18,00|#{vl_icms}|0,00|0,00|0,00|0|50||1000,00|0,00|0,00|01|1000,00|0,65||0,00|6,50|01|1000,00|3,00||0,00|30,00|CTA||0,00|"
  end

  def c190_line(vl_icms: "180,00")
    "|C190|000|5102|18,00|1000,00|1000,00|#{vl_icms}|0,00|0,00|0,00|0,00||"
  end

  it "parses the EFD with layout-as-data and reconciles pointing to record and document" do
    ok = import_doc(100)
    missing = import_doc(101)                      # autorizada, ficará fora do arquivo
    cancelled = import_doc(102, cancelled: true)   # cancelada, escriturada como regular
    mism = import_doc(103)                         # VL_ICMS e CFOP do item divergentes

    sped = <<~TXT
      |0000|020|0|01072026|31072026|CLIENTE EXEMPLO|12345678000190||SP|123456789012|3550308|||A|0|
      |0001|0|
      |0150|CLI001|DESTINATARIO|1058|99887766000155||987654321098|3550308|||||
      |C001|0|
      #{c100_line(100)}
      #{c170_line}
      #{c190_line}
      #{c100_line(102)}
      #{c100_line(103, vl_icms: "150,00")}
      #{c170_line(cfop: "5405", vl_icms: "150,00")}
      #{c190_line(vl_icms: "150,00")}
      #{c100_line(999)}
      |9999|13|
    TXT

    file = Ingestion::Sped::Parser.call(sped, client:, storage_ref: "spec/sped.txt")
    expect(file.state).to eq("done")
    expect(file.period_start).to eq(Date.new(2026, 7, 1))
    expect(file.summary["c100"]).to eq(4)
    expect(file.records.find_by(record_type: "C100", document_access_key: key_for(100)).document_id).to eq(ok.id)
    expect(file.records.find_by(record_type: "C170").fields).to include("CFOP" => "5102", "VL_ICMS" => "180.00", "CST_IPI" => "50")   # decimal normalizado + leiaute oficial
    c170 = file.records.find_by(record_type: "C170")
    expect(c170.parent_id).to eq(file.records.find_by(record_type: "C100", document_access_key: key_for(100)).id)   # hierarquia por nível

    run = client.audit_runs.create!(firm_id: client.firm_id, period_start: Date.new(2026, 7, 1), period_end: Date.new(2026, 7, 31))
    Audit::Runner.new(run).call
    run.reload
    expect(run.snapshot["fiscal_file_id"]).to eq(file.id)
    sped_findings = run.findings.where("rule_code LIKE 'SPED.%'").group(:rule_code).count
    expect(sped_findings["SPED.DOC.MISSING_IN_FILE"]).to eq(2)   # nota 101 fora do arquivo + C100 999 sem XML
    expect(sped_findings["SPED.DOC.CANCELLED_SIT"]).to eq(1)
    expect(sped_findings["SPED.DOC.VALUES"]).to be >= 1
    expect(sped_findings["SPED.ITEM.MISMATCH"]).to be >= 2       # CFOP e VL_ICMS do item
    expect(sped_findings["SPED.DOC.NO_ANALYTIC"]).to be >= 1     # C100 999 sem C190

    f = run.findings.find_by(rule_code: "SPED.DOC.VALUES")
    expect(f.document_id).to eq(mism.id)
    expect(f.fiscal_record_id).to be_present
    expect(f.evidence).to include("field" => "VL_ICMS", "file_value" => "150.0", "xml_value" => "180.0")
    not_in_xml = run.findings.where(rule_code: "SPED.DOC.MISSING_IN_FILE").find { |x| x.evidence["access_key"] == key_for(999) }
    expect(not_in_xml.fiscal_record_id).to be_present
    cancelled_f = run.findings.find_by(rule_code: "SPED.DOC.CANCELLED_SIT")
    expect(cancelled_f.document_id).to eq(cancelled.id)
  end
end
