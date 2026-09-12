require "rails_helper"
require Rails.root.join("lib/rule_case_builder")

# A12/M8/M9/M10: valor fiscal vem da regra e item inavaliável não pode virar "não tem a evidência".
RSpec.describe "primitivas: parâmetros obrigatórios e itens inavaliáveis" do
  def doc(items:, over: {})
    RuleCaseBuilder.doc(items:, doc: over).merge("_id" => 1, "role" => "issuer")
  end

  describe Rules::Primitives::ScenarioFieldDisagreement do
    let(:evidence) { { "field" => "item.ipi.amount", "op" => "gt", "value" => 0 } }
    def call(items, threshold: "0.1")
      described_class.new({ "field" => "ipi_taxpayer", "when_field_is" => false, "threshold" => threshold, "evidence" => evidence },
                          { "period" => { "documents" => [doc(items:)] }, "scenario" => { "ipi_taxpayer" => false } }).call
    end

    it "excludes unevaluable items from the denominator and exposes the count" do
      items = [RuleCaseBuilder.normal_item("number" => 1, "ipi" => { "cst" => "50", "amount" => "10.00" })] +
              (2..10).map { |n| RuleCaseBuilder.normal_item("number" => n) }
      hit = call(items).first
      expect(hit).not_to be_nil                                   # 1/10 = 10% não passaria do threshold; 1/1 avaliável = 100% passa
      expect(hit[:evidence]).to include("share_pct" => 100, "matching_items" => 1, "evaluated_items" => 1, "unevaluable_items" => 9, "total_items" => 10)
    end

    it "raises an evaluation error when no item can be evaluated" do
      expect { call((1..3).map { |n| RuleCaseBuilder.normal_item("number" => n) }) }
        .to raise_error(Rules::EvaluationError, /inavaliável em todos/)
    end

    it "compares the share in BigDecimal against the threshold" do
      items = (1..10).map { |n| RuleCaseBuilder.normal_item("number" => n, "ipi" => { "cst" => "50", "amount" => n <= 3 ? "10.00" : "0.00" }) }
      expect(call(items, threshold: "0.3")).to eq([])              # 3/10 == 0.3 exato: não dispara
      expect(call(items, threshold: "0.29").first[:evidence]).to include("share_pct" => 30)
    end
  end

  describe Rules::Primitives::EventConsistency do
    let(:document) { doc(items: [RuleCaseBuilder.normal_item], over: { "issuance" => { "issued_at" => "2026-07-10T10:00:00-03:00" } }) }
    let(:event) { { "access_key" => document["access_key"], "event" => { "kind" => "cancellation", "occurred_at" => "2026-07-11T20:30:00-03:00" } } }
    def ctx = { "period" => { "documents" => [document], "events" => [event] } }

    it "requires the legal deadline as a rule param" do
      expect { described_class.new({}, ctx).call }.to raise_error(Rules::EvaluationError, /cancellation_deadline_hours/)
    end

    it "counts the hours after issuance with the deadline from the rule" do
      hit = described_class.new({ "cancellation_deadline_hours" => 24 }, ctx).call.first
      expect(hit[:evidence]).to include("problem" => "late_cancellation", "hours_after_issue" => 35)
      expect(described_class.new({ "cancellation_deadline_hours" => 48 }, ctx).call).to eq([])
    end

    it "turns an unparseable date into an evaluation error" do
      document["issuance"]["issued_at"] = "data-invalida"
      expect { described_class.new({ "cancellation_deadline_hours" => 24 }, ctx).call }.to raise_error(Rules::EvaluationError, /não é data\/hora/)
    end
  end

  describe Rules::Primitives::SpedDocumentReconciliation do
    def key(n) = "35260712345678000190550010000#{n.to_s.rjust(6, '0')}1000#{n.to_s.rjust(6, '0')}"
    def c100(n, over = {})
      { "record_id" => n, "line" => n, "access_key" => key(n),
        "fields" => { "IND_OPER" => "1", "IND_EMIT" => "0", "COD_MOD" => "55", "COD_SIT" => "00", "SER" => "1", "NUM_DOC" => n.to_s }.merge(over) }
    end
    let(:saida) { doc(items: [RuleCaseBuilder.normal_item], over: { "access_key" => key(100), "issuance" => { "number" => 100 } }).merge("operation" => { "direction" => "outbound" }) }
    # NF-e de emissão própria de ENTRADA (devolução/retorno de industrialização): o XML está na base como inbound
    let(:entrada) { doc(items: [RuleCaseBuilder.normal_item], over: { "access_key" => key(200), "issuance" => { "number" => 200 } }).merge("operation" => { "direction" => "inbound" }) }
    let(:params) { { "check" => "presence", "models" => %w[55 65], "own_issue_ind_emit" => "0" } }
    def ctx(file) = { "fiscal_file" => file, "period" => { "documents" => [saida, entrada] } }

    it "requires models and IND_EMIT from the rule (Guia Prático, tabela 4.1.2)" do
      expect { described_class.new({ "check" => "presence" }, ctx("c100" => [])).call }.to raise_error(Rules::EvaluationError, /'models'/)
      expect { described_class.new({ "check" => "presence", "models" => %w[55] }, ctx("c100" => [])).call }.to raise_error(Rules::EvaluationError, /own_issue_ind_emit/)
      expect { described_class.new({ "check" => "cancelled", "models" => %w[55] }, ctx("c100" => [])).call }.to raise_error(Rules::EvaluationError, /cancelled_cod_sit/)
      expect { described_class.new({ "check" => "values", "models" => %w[55] }, ctx("c100" => [])).call }.to raise_error(Rules::EvaluationError, /values_cod_sit/)
      expect { described_class.new({ "check" => "analytic", "models" => %w[55], "own_issue_ind_emit" => "0" }, ctx("c100" => [])).call }.to raise_error(Rules::EvaluationError, /analytic_cod_sit/)
    end

    it "does not flag an inbound own-issued C100 whose XML is in the base" do
      hits = described_class.new(params, ctx("c100" => [c100(100), c100(200, "IND_OPER" => "0")])).call
      expect(hits).to eq([])
    end

    it "still flags a C100 without any XML in the base" do
      hits = described_class.new(params, ctx("c100" => [c100(100), c100(999)])).call
      expect(hits.map { |h| h[:vars]["problem"] }).to eq(["not_in_xml"])
      expect(hits.first[:evidence]["access_key"]).to eq(key(999))
    end
  end

  describe Audit::Stats do
    let(:items) { [RuleCaseBuilder.normal_item("number" => 1)] }
    let(:authorized) { doc(items:).merge("status" => { "state" => "authorized" }) }
    let(:cancelled) { doc(items:).merge("status" => { "state" => "cancelled" }) }
    let(:condition) { { "field" => "item.icms.cst", "op" => "eq", "value" => "00" } }

    it "ignores items of cancelled documents" do
      expect(described_class.new([authorized, cancelled]).count(condition)).to eq(1)
    end

    it "returns fractions in BigDecimal and does not count unevaluable items as false" do
      stats = described_class.new([authorized])
      expect(stats.share(condition)).to eq(BigDecimal(1))
      expect(stats.share(condition)).to be_a(BigDecimal)
      expect(stats.distribution("item.icms.cst").values.first).to be_a(BigDecimal)
      absent = { "field" => "item.ipi.amount", "op" => "gt", "value" => 0 }
      expect(stats.share(absent)).to eq(BigDecimal(0))
      expect(stats.unevaluable(absent)).to eq(1)
    end
  end
  # A8: quantidade não numérica no XML e devolução sem itens não podem derrubar o run inteiro.
  describe Rules::Primitives::ReturnReferencesOriginal do
    def ctx(returns:, originals:)
      { "period" => { "documents" => originals + returns } }
    end

    def sale(key:, qty: "10.0000")
      RuleCaseBuilder.doc(items: [RuleCaseBuilder.normal_item("number" => 1, "product" => { "code" => "P1", "commercial_quantity" => qty })])
                     .merge("_id" => 1, "role" => "issuer", "access_key" => key, "kind" => "nfe")
    end

    def ret(key:, qty:, items: :default)
      d = RuleCaseBuilder.doc(items: items == :default ? [RuleCaseBuilder.normal_item("number" => 1, "product" => { "code" => "P1", "commercial_quantity" => qty })] : [])
      d = d.merge("_id" => 2, "role" => "issuer", "access_key" => "R#{key}", "kind" => "nfe", "monitored_cnpj" => d.dig("issuer", "cnpj"),
                  "issuance" => d["issuance"].to_h.merge("purpose" => "return"),
                  "references" => [{ "access_key" => key, "kind" => "nfe", "resolved" => true }])
      d["items"] = nil if items == :nil
      d
    end

    it "turns a non-numeric quantity into an evaluation error, never ArgumentError" do
      c = ctx(originals: [sale(key: "K1")], returns: [ret(key: "K1", qty: "abc")])
      expect { described_class.new({ "check" => %w[exceeds], "tolerance" => "0" }, c).call }
        .to raise_error(Rules::EvaluationError)
    end

    it "survives a return document without items" do
      c = ctx(originals: [sale(key: "K1")], returns: [ret(key: "K1", qty: "1", items: :nil)])
      expect { described_class.new({ "check" => %w[exceeds], "tolerance" => "0" }, c).call }.not_to raise_error
    end
  end

end
