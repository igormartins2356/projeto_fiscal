require "rails_helper"

RSpec.describe "upload → parse → audit → findings" do
  before { seed_all! }

  let(:client) { Accounts::Client.find_by!(cnpj: "12345678000190") }

  it "imports the XML with derivations and produces the expected findings" do
    result = Ingestion::DocumentImporter.new(client:).call(nfe_fixture("sale_return_csosn_102"))
    expect(result.status).to eq(:created)
    doc = result.document
    expect(doc.role).to eq("issuer")
    expect(doc.operation_nature).to eq("sale_return")
    expect(doc.status_state).to eq("authorized")
    item = doc.items.first.data
    expect(item).to include("net_amount" => "1000.00", "cfop_nature" => "sale_return", "cfop_group" => "inbound_intrastate", "cfop_scope" => "intrastate")
    expect(item["icms"]).to include("situation_code" => "102", "situation_field" => "csosn", "taxation_kind" => "simples_without_credit")
    expect(item["ibs_cbs"]["schedule_rates"]).to include("cbs" => "0.90")
    expect(doc.data["totals"]["totals_mismatch"]).to eq({})

    expect(Ingestion::DocumentImporter.new(client:).call(nfe_fixture("sale_return_csosn_102")).status).to eq(:duplicate)

    run = client.audit_runs.create!(firm_id: client.firm_id, period_start: Date.new(2026, 3, 1), period_end: Date.new(2026, 3, 31))
    Audit::Runner.new(run).call
    run.reload
    expect(run.state).to eq("done")
    # tolerância nominal: só estas tabelas ainda não têm versão publicada no seed (regra vira evaluation_error, não finding)
    missing_tables = run.evaluation_errors.filter_map { |e| e["error"][/tabela '([a-z_]+)' sem versão publicada/, 1] }
    expect(missing_tables).to match_array(%w[ibs_cbs_class tipi pis_cofins_special])
    expect(run.evaluation_errors.size).to eq(missing_tables.size)
    codes = run.findings.pluck(:rule_code)
    expect(codes).to include("DOC.RETURN.ORIGINAL_MISSING")   # devolução da própria venda, original não enviada
    expect(codes).not_to include("ICMS.CSOSN.SALE_RETURN", "ICMS.REGIME.SITUATION_FIELD", "DOC.TOTALS.ITEMS_SUM", "CFOP.SCOPE.MATCH", "IBSCBS.GROUP.REQUIRED", "IBSCBS.CBS.RATE_SCHEDULE", "DOC.RETURN.REFERENCE", "DOC.RETURN.MIRROR")
    f = run.findings.find_by(rule_code: "DOC.RETURN.ORIGINAL_MISSING")
    expect(f.severity).to eq("warning")
    expect(f.evidence).to include("referenced_access_key" => "35260312345678000190550010000009991000009999")
    expect(run.snapshot["rule_ids"]).to be_present
    expect(run.snapshot["reference_version_ids"]).to include("icms_internal_rate", "icms_interstate_rate")
    expect(Catalog::ReferenceVersion.where(id: run.snapshot["reference_version_ids"].values).pluck(:state).uniq).to eq(["published"])
  end

  it "não avalia regra de item nem de documento em nota cancelada" do
    doc = Ingestion::DocumentImporter.new(client:).call(nfe_fixture("sale_return_csosn_102")).document
    data = doc.data.deep_dup
    data["status"] = (data["status"] || {}).merge("state" => "cancelled")
    doc.update!(status_state: "cancelled", data:)

    run = client.audit_runs.create!(firm_id: client.firm_id, period_start: Date.new(2026, 3, 1), period_end: Date.new(2026, 3, 31))
    Audit::Runner.new(run).call
    scopes = run.reload.findings.where(document_id: doc.id).distinct.pluck(:scope)
    expect(scopes).not_to include("item", "document")
  end

  it "keeps the finding state across runs (dedupe_key) and honours client overrides" do
    Ingestion::DocumentImporter.new(client:).call(nfe_fixture("sale_return_csosn_102"))
    run1 = client.audit_runs.create!(firm_id: client.firm_id, period_start: Date.new(2026, 3, 1), period_end: Date.new(2026, 3, 31))
    Audit::Runner.new(run1).call
    run1.findings.find_by!(rule_code: "DOC.RETURN.ORIGINAL_MISSING").update!(state: "justified", state_note: "cliente tem entendimento próprio")

    run2 = client.audit_runs.create!(firm_id: client.firm_id, period_start: Date.new(2026, 3, 1), period_end: Date.new(2026, 3, 31))
    Audit::Runner.new(run2).call
    expect(run2.findings.find_by!(rule_code: "DOC.RETURN.ORIGINAL_MISSING").state).to eq("justified")

    Rules::RuleOverride.create!(rule_code: "DOC.RETURN.ORIGINAL_MISSING", source_type: "client", source_id: client.id, override_action: "disable",
                                effective_from: Date.new(2026, 1, 1), justification: "decisão do contador", created_by: Accounts::User.first)
    run3 = client.audit_runs.create!(firm_id: client.firm_id, period_start: Date.new(2026, 3, 1), period_end: Date.new(2026, 3, 31))
    Audit::Runner.new(run3).call
    expect(run3.findings.pluck(:rule_code)).not_to include("DOC.RETURN.ORIGINAL_MISSING")
  end
end
