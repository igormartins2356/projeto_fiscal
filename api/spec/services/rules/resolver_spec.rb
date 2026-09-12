require "rails_helper"

# A9/A11: sombra coexiste com a publicada; overrides não podem apagar severity/vigência nem trocar a regra no escopo do cliente.
RSpec.describe Rules::Resolver do
  let(:firm) { Accounts::Firm.create!(name: "Firma") }
  let(:user) { Accounts::User.create!(firm:, name: "Ana", email: "ana@resolver.test", password: "senha-forte-123", role: "firm_admin") }
  let(:client) { Accounts::Client.create!(firm:, cnpj: "12345678000190", legal_name: "C", uf: "SP") }
  let(:date) { Date.new(2026, 7, 31) }
  let(:body) { { "assert" => { "field" => "item.icms.cst", "op" => "present" }, "message" => "CST ausente" } }

  def rule!(version:, state:, severity: "error")
    Rules::Rule.create!(code: "TEST.RESOLVER.RULE", version:, title: "t#{version}", scope: "item", severity:, state:,
                        effective_from: Date.new(2020, 1, 1), source_type: "platform", body:)
  end

  def override!(action, patch, source_type: "client", effective_from: Date.new(2020, 1, 1))
    Rules::RuleOverride.create!(rule_code: "TEST.RESOLVER.RULE", source_type:, source_id: source_type == "client" ? client.id : firm.id,
                                override_action: action, patch:, effective_from:, justification: "consulta formal", created_by: user)
  end

  def resolve = described_class.new(client:, date:)

  it "keeps the published rule when a shadow version of the same code exists" do
    published = rule!(version: 1, state: "published")
    shadow = rule!(version: 2, state: "shadow")
    resolved = resolve.call.select { |r| r.rule.code == "TEST.RESOLVER.RULE" }
    expect(resolved.map { |r| r.rule.id }).to contain_exactly(published.id, shadow.id)
    expect(resolved.count { |r| r.rule.shadow? }).to eq(1)
  end

  it "keeps only the highest published version per code" do
    rule!(version: 1, state: "published")
    v2 = rule!(version: 2, state: "published")
    expect(resolve.call.select { |r| r.rule.code == "TEST.RESOLVER.RULE" }.map { |r| r.rule.id }).to eq([v2.id])
  end

  it "ignores a client replace and keeps the platform definition" do
    rule!(version: 1, state: "published")
    # O model já recusa gravar um replace de cliente; a defesa do Resolver continua valendo para linha antiga.
    ov = Rules::RuleOverride.new(rule_code: "TEST.RESOLVER.RULE", source_type: "client", source_id: client.id, override_action: "replace",
                                 patch: { "assert" => { "field" => "item.number", "op" => "present" }, "message" => "outra" },
                                 effective_from: Date.new(2020, 1, 1), justification: "consulta formal", created_by: user)
    ov.save!(validate: false)
    r = resolve.call.find { |x| x.rule.code == "TEST.RESOLVER.RULE" }
    expect(r.definition["message"]).to eq("CST ausente")
    expect(r.source).to eq("platform")
    expect(r.override_ids).not_to include(ov.id)
    expect(resolve.tap(&:call).warnings.join).to include("só é permitido no escopo da firma")
  end

  it "keeps severity, version and effective dates on a firm replace" do
    rule!(version: 3, state: "published", severity: "warning")
    override!("replace", { "assert" => { "field" => "item.number", "op" => "present" }, "message" => "outra" }, source_type: "firm")
    d = resolve.call.find { |x| x.rule.code == "TEST.RESOLVER.RULE" }.definition
    expect(d).to include("code" => "TEST.RESOLVER.RULE", "scope" => "item", "severity" => "warning", "version" => 3, "message" => "outra")
    expect(d["effective_from"]).to eq(Date.new(2020, 1, 1))
    expect(Rules::Validator.new(d).valid?).to be(true), Rules::Validator.new(d).errors.inspect
  end

  it "applies the most recent override of the same scope" do
    rule!(version: 1, state: "published")
    override!("adjust", { "severity" => "warning" }, source_type: "firm", effective_from: Date.new(2021, 1, 1))
    override!("adjust", { "severity" => "info" }, source_type: "firm", effective_from: Date.new(2020, 1, 1))
    expect(resolve.call.find { |x| x.rule.code == "TEST.RESOLVER.RULE" }.definition["severity"]).to eq("warning")
  end
end
