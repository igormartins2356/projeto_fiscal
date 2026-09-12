require "rails_helper"

RSpec.describe Audit::Runner do
  before { seed_all! }

  let(:client) { Accounts::Client.find_by!(cnpj: "12345678000190") }

  def build_document(number:, reference_date:, csosn: "102", client_record: client)
    key = "3526031234567800019055001#{format('%09d', number)}1000009999"
    doc = Ingestion::Document.create!(
      firm_id: client_record.firm_id, client_id: client_record.id, kind: "nfe", model: "55", access_key: key,
      xml_hash: Digest::SHA256.hexdigest(key), xml_ref: "spec/#{key}.xml", role: "issuer", reference_date:,
      period: reference_date.strftime("%Y-%m"), issued_at: reference_date.to_time, series: "1", number:,
      issuer_cnpj: client_record.cnpj, status_state: "authorized", operation_nature: "sale", total_amount: "100.00",
      data: { "access_key" => key, "kind" => "nfe", "model" => "55", "role" => "issuer", "number" => number, "series" => "1",
              "reference_date" => reference_date.to_s, "status" => { "state" => "authorized" },
              "operation" => { "nature" => "sale", "destination_uf" => "SP", "origin_uf" => "SP" },
              "issuer" => { "cnpj" => client_record.cnpj, "uf" => "SP" }, "totals" => { "document_amount" => "100.00" } }
    )
    doc.items.create!(client_id: client_record.id, number: 1, ncm: "30049099", cfop: "5102", icms_situation_code: csosn,
                      net_amount: "100.00",
                      data: { "number" => 1, "is_service" => false, "net_amount" => "100.00",
                              "product" => { "ncm" => "30049099" }, "cfop" => "5102",
                              "icms" => { "csosn" => csosn, "situation_code" => csosn } })
    doc
  end

  def create_rule!(code:, version:, effective_from:, effective_until: nil, body:, scope: "item", state: "published")
    Rules::Rule.create!(code:, version:, title: "Regra de teste #{code} v#{version}", scope:, severity: "error", state:,
                        effective_from:, effective_until:, source_type: "platform", published_at: Time.current, body:)
  end

  def run_audit!(period_start: Date.new(2026, 3, 1), period_end: Date.new(2026, 3, 31), client_record: client)
    run = client_record.audit_runs.create!(firm_id: client_record.firm_id, period_start:, period_end:)
    described_class.new(run).call
    run.reload
  end

  describe "resolução temporal (A10)" do
    before do
      csosn_rule = ->(expected) {
        { "applies_when" => { "field" => "doc.role", "op" => "eq", "value" => "issuer" },
          "assert" => { "field" => "item.icms.csosn", "op" => "eq", "value" => expected },
          "message" => "CSOSN esperado #{expected}" }
      }
      create_rule!(code: "TEST.TEMPORAL.CSOSN", version: 1, effective_from: Date.new(2026, 1, 1),
                   effective_until: Date.new(2026, 3, 14), body: csosn_rule.("102"))
      create_rule!(code: "TEST.TEMPORAL.CSOSN", version: 2, effective_from: Date.new(2026, 3, 15), body: csosn_rule.("900"))
      build_document(number: 1, reference_date: Date.new(2026, 3, 10), csosn: "102")
      build_document(number: 2, reference_date: Date.new(2026, 3, 20), csosn: "102")
    end

    it "avalia cada documento com a versão da regra vigente na sua data de emissão" do
      run = run_audit!
      findings = run.findings.where(rule_code: "TEST.TEMPORAL.CSOSN").includes(:document, :rule)
      expect(findings.map { |f| [f.document.reference_date, f.rule.version] })
        .to eq([[Date.new(2026, 3, 20), 2]])
    end

    it "registra no snapshot as versões usadas por intervalo de vigência" do
      run = run_audit!
      intervals = run.snapshot["by_interval"]
      slice = intervals.find { |i| i["from"] == "2026-03-01" }
      later = intervals.find { |i| i["from"] == "2026-03-15" }
      expect(slice["to"]).to eq("2026-03-14")
      expect(Rules::Rule.where(id: slice["rule_ids"], code: "TEST.TEMPORAL.CSOSN").pluck(:version)).to eq([1])
      expect(Rules::Rule.where(id: later["rule_ids"], code: "TEST.TEMPORAL.CSOSN").pluck(:version)).to eq([2])
      expect(run.snapshot["rule_ids"]).to be_present
    end
  end

  describe "sobreposição de linha de tabela no snapshot (M14)" do
    it "grava os ids de ReferenceRowOverride consultados" do
      table = Catalog::ReferenceTable.find_by!(code: "icms_internal_rate")
      override = Catalog::ReferenceRowOverride.create!(reference_table: table, source_type: "client", source_id: client.id,
                                                       key: %w[SP *], data: { "rate" => "17.00", "fcp_rate" => "0.00" },
                                                       effective_from: Date.new(2026, 1, 1), justification: "regime especial",
                                                       created_by: Accounts::User.first)
      create_rule!(code: "TEST.LOOKUP.RATE", version: 1, effective_from: Date.new(2026, 1, 1),
                   body: { "let" => [{ "as" => "expected_row", "lookup" => "icms_internal_rate",
                                       "key" => [{ "ref" => "doc.operation.destination_uf" }, "*"] }],
                           "applies_when" => { "field" => "doc.role", "op" => "eq", "value" => "issuer" },
                           "assert" => { "field" => "expected_row.rate", "op" => "eq", "value" => "99.00" },
                           "message" => "alíquota interna {{expected_row.rate}}" })
      build_document(number: 3, reference_date: Date.new(2026, 3, 10))

      run = run_audit!
      expect(run.snapshot["reference_row_override_ids"]).to include(override.id)
      expect(run.findings.find_by!(rule_code: "TEST.LOOKUP.RATE").message).to eq("alíquota interna 17.00")
    end
  end

  describe "regra em sombra coexistindo com a publicada" do
    before do
      body = { "applies_when" => { "field" => "doc.role", "op" => "eq", "value" => "issuer" },
               "assert" => { "field" => "item.icms.csosn", "op" => "eq", "value" => "900" },
               "message" => "CSOSN esperado 900" }
      create_rule!(code: "TEST.SHADOW.CSOSN", version: 1, effective_from: Date.new(2026, 1, 1), body:)
      create_rule!(code: "TEST.SHADOW.CSOSN", version: 2, effective_from: Date.new(2026, 1, 1), body:, state: "shadow")
      build_document(number: 8, reference_date: Date.new(2026, 3, 10), csosn: "102")
    end

    it "persiste os dois disparos quando sombra e publicada apontam o mesmo alvo com a mesma evidência" do
      run = run_audit!
      findings = run.findings.where(rule_code: "TEST.SHADOW.CSOSN")
      expect(findings.pluck(:shadow).sort_by(&:to_s)).to eq([false, true])
      expect(findings.pluck(:dedupe_key).uniq.size).to eq(2)
    end
  end

  describe "herança de estado entre runs (M22)" do
    before do
      create_rule!(code: "TEST.STATE.CSOSN", version: 1, effective_from: Date.new(2026, 1, 1),
                   body: { "applies_when" => { "field" => "doc.role", "op" => "eq", "value" => "issuer" },
                           "assert" => { "field" => "item.icms.csosn", "op" => "eq", "value" => "900" },
                           "message" => "CSOSN esperado 900" })
      build_document(number: 4, reference_date: Date.new(2026, 3, 10), csosn: "102")
    end

    it "não herda 'fixed': o apontamento que reaparece nasce aberto" do
      run1 = run_audit!
      run1.findings.find_by!(rule_code: "TEST.STATE.CSOSN").update!(state: "fixed")
      run2 = run_audit!
      expect(run2.findings.find_by!(rule_code: "TEST.STATE.CSOSN").state).to eq("open")
    end

    it "herda o estado posto pelo contador (justified)" do
      run1 = run_audit!
      run1.findings.find_by!(rule_code: "TEST.STATE.CSOSN").update!(state: "justified", state_note: "regime especial")
      run2 = run_audit!
      finding = run2.findings.find_by!(rule_code: "TEST.STATE.CSOSN")
      expect([finding.state, finding.state_note]).to eq(["justified", "regime especial"])
    end

    it "usa o último estado do dedupe_key: justificado e depois corrigido volta a abrir" do
      run1 = run_audit!
      run1.findings.find_by!(rule_code: "TEST.STATE.CSOSN").update!(state: "justified", state_note: "regime especial")
      run2 = run_audit!
      run2.findings.find_by!(rule_code: "TEST.STATE.CSOSN").update!(state: "fixed")
      run3 = run_audit!
      expect(run3.findings.find_by!(rule_code: "TEST.STATE.CSOSN").state).to eq("open")
    end
  end

  describe "idempotência do run (A13)" do
    before do
      create_rule!(code: "TEST.RETRY.CSOSN", version: 1, effective_from: Date.new(2026, 1, 1),
                   body: { "applies_when" => { "field" => "doc.role", "op" => "eq", "value" => "issuer" },
                           "assert" => { "field" => "item.icms.csosn", "op" => "eq", "value" => "900" },
                           "message" => "CSOSN esperado 900" })
      build_document(number: 5, reference_date: Date.new(2026, 3, 10), csosn: "102")
    end

    it "repetir o mesmo run (retentativa do job) não colide no índice único nem duplica findings" do
      run = client.audit_runs.create!(firm_id: client.firm_id, period_start: Date.new(2026, 3, 1), period_end: Date.new(2026, 3, 31))
      described_class.new(run).call
      first = run.reload.findings.count
      expect { described_class.new(run).call }.not_to raise_error
      expect(run.reload.findings.count).to eq(first)
      expect(run.findings.where(rule_code: "TEST.RETRY.CSOSN").count).to eq(1)
    end

    it "preserva a justificativa ao reprocessar o MESMO run" do
      run = client.audit_runs.create!(firm_id: client.firm_id, period_start: Date.new(2026, 3, 1), period_end: Date.new(2026, 3, 31))
      described_class.new(run).call
      run.reload.findings.find_by!(rule_code: "TEST.RETRY.CSOSN").update!(state: "justified", state_note: "acordo com o cliente")
      described_class.new(run).call
      finding = run.reload.findings.find_by!(rule_code: "TEST.RETRY.CSOSN")
      expect([finding.state, finding.state_note]).to eq(["justified", "acordo com o cliente"])
    end

    it "não deixa findings órfãos quando a finalização do run falha" do
      run = client.audit_runs.create!(firm_id: client.firm_id, period_start: Date.new(2026, 3, 1), period_end: Date.new(2026, 3, 31))
      allow(Audit::Coverage).to receive(:new).and_wrap_original do |original, *args|
        instance = original.call(*args)
        allow(instance).to receive(:result).and_raise("falha ao finalizar")
        instance
      end
      expect { described_class.new(run).call }.to raise_error("falha ao finalizar")
      expect(run.reload.state).to eq("failed")
      expect(run.findings.count).to eq(0)
    end
  end

  describe "escopo de período com vigência parcial" do
    def period_rule_body = { "params" => { "enabled" => true },
                             "applies_when" => { "field" => "params.enabled", "op" => "present" },
                             "assert" => { "field" => "params.enabled", "op" => "absent" },
                             "message" => "apuração do período" }

    before do
      create_rule!(code: "TEST.PERIOD.ENDED", version: 1, scope: "period", effective_from: Date.new(2026, 1, 1),
                   effective_until: Date.new(2026, 3, 14), body: period_rule_body)
      create_rule!(code: "TEST.PERIOD.WHOLE", version: 1, scope: "period", effective_from: Date.new(2026, 1, 1),
                   body: period_rule_body)
      build_document(number: 9, reference_date: Date.new(2026, 3, 10), csosn: "102")
    end

    it "avalia a regra de período cuja vigência termina no meio do período" do
      run = run_audit!
      expect(run.snapshot["by_interval"].size).to eq(2)
      expect(run.findings.where(rule_code: "TEST.PERIOD.ENDED").count).to eq(1)
      expect(run.evaluation_errors.map { |e| e["rule_code"] }).not_to include("TEST.PERIOD.ENDED")
    end

    it "avalia a regra vigente no período inteiro uma única vez, mesmo com várias fatias" do
      run = run_audit!
      expect(run.findings.where(rule_code: "TEST.PERIOD.WHOLE").count).to eq(1)
    end
  end

  describe "dependência de cenário (M23)" do
    let(:no_scenario_client) do
      Accounts::Client.create!(firm_id: client.firm_id, cnpj: "99887766000155", legal_name: "Sem Cenário Ltda", uf: "SP")
    end

    it "não pula regra que apenas cita 'scenario.' na mensagem" do
      create_rule!(code: "TEST.SCENARIO.MESSAGE", version: 1, effective_from: Date.new(2026, 1, 1),
                   body: { "applies_when" => { "field" => "doc.role", "op" => "eq", "value" => "issuer" },
                           "assert" => { "field" => "item.icms.csosn", "op" => "eq", "value" => "900" },
                           "message" => "scenario.tax_regime do cliente não explica o CSOSN informado" })
      build_document(number: 6, reference_date: Date.new(2026, 3, 10), csosn: "102", client_record: no_scenario_client)

      run = run_audit!(client_record: no_scenario_client)
      expect(run.findings.pluck(:rule_code)).to include("TEST.SCENARIO.MESSAGE")
    end

    it "continua pulando regra que lê scenario.* em field/ref quando o cliente não tem cenário publicado" do
      create_rule!(code: "TEST.SCENARIO.FIELD", version: 1, effective_from: Date.new(2026, 1, 1),
                   body: { "applies_when" => { "field" => "scenario.tax_regime", "op" => "eq", "value" => "simples_nacional" },
                           "assert" => { "field" => "item.icms.csosn", "op" => "eq", "value" => "900" },
                           "message" => "CSOSN esperado 900 no Simples" })
      build_document(number: 7, reference_date: Date.new(2026, 3, 10), csosn: "102", client_record: no_scenario_client)

      run = run_audit!(client_record: no_scenario_client)
      expect(run.findings.pluck(:rule_code)).not_to include("TEST.SCENARIO.FIELD")
      expect(run.evaluation_errors.map { |e| e["rule_code"] }).to include("SCENARIO")
    end
  end
end
