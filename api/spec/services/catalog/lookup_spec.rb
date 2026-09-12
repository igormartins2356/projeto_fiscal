require "rails_helper"

# [M13] overrides carregados de uma vez; [M14] ids usados expostos; [M15] escolha determinística entre vigentes.
RSpec.describe Catalog::Lookup do
  let(:firm) { Accounts::Firm.create!(name: "Firma") }
  let(:user) { Accounts::User.create!(firm:, name: "Ana", email: "ana@x.com", password: "senha-forte-123", role: "firm_admin") }
  let(:client) { Accounts::Client.create!(firm:, cnpj: "12345678000190", legal_name: "C", uf: "SP") }
  let(:table) { Catalog::ReferenceTable.create!(code: "lk_table", name: "Tabela", key_arity: 2, key_names: %w[uf ncm]) }
  let(:date) { Date.new(2026, 3, 1) }

  before do
    v = table.versions.create!(version: 1, effective_from: Date.new(2026, 1, 1), state: "published", published_at: Time.current)
    Catalog::ReferenceRow.insert_all!(%w[SP MG RJ ES PR].map { |uf| { reference_version_id: v.id, key: [uf, "*"], data: { "rate" => "18.00" }, legal_basis: "RICMS" } })
  end

  def override!(source_type, source_id, key, rate, effective_from)
    Catalog::ReferenceRowOverride.new(reference_table: table, source_type:, source_id:, key:, data: { "rate" => rate },
                                      effective_from:, justification: "regime especial", created_by: user).tap { |o| o.save!(validate: false) }
  end

  def count_queries
    n = 0
    sub = ActiveSupport::Notifications.subscribe("sql.active_record") { |*, payload| n += 1 unless payload[:name] == "SCHEMA" || payload[:sql] =~ /\A(BEGIN|COMMIT|SAVEPOINT|RELEASE)/ }
    yield
    ActiveSupport::Notifications.unsubscribe(sub)
    n
  end

  it "carrega os overrides da firma/cliente uma vez, e não por lookup" do
    override!("client", client.id, %w[SP *], "12.00", Date.new(2026, 1, 1))
    lookup = described_class.new(date:, firm_id: firm.id, client_id: client.id)
    queries = count_queries { 50.times { |i| lookup.lookup("lk_table", [%w[SP MG RJ ES PR][i % 5], "*"]) } }
    expect(queries).to be < 10
    expect(lookup.lookup("lk_table", %w[SP *])).to include("rate" => "12.00", "_source" => "client")
    expect(lookup.lookup("lk_table", %w[MG *])).to include("rate" => "18.00", "_source" => "platform")
  end

  it "expõe os ids das linhas sobrepostas usadas (M14)" do
    o = override!("firm", firm.id, %w[MG *], "12.00", Date.new(2026, 1, 1))
    lookup = described_class.new(date:, firm_id: firm.id, client_id: client.id)
    expect(lookup.row_override_ids_used).to eq([])
    lookup.lookup("lk_table", %w[SP *])
    expect(lookup.row_override_ids_used).to eq([])
    2.times { lookup.lookup("lk_table", %w[MG *]) }
    expect(lookup.row_override_ids_used).to eq([o.id])
  end

  it "com dois overrides vigentes, escolhe o de vigência mais recente (M15)" do
    old = override!("client", client.id, %w[SP *], "10.00", Date.new(2026, 1, 1))
    recent = override!("client", client.id, %w[SP *], "20.00", Date.new(2026, 2, 1))
    got = described_class.new(date:, firm_id: firm.id, client_id: client.id).lookup("lk_table", %w[SP *])
    expect(got["_override_id"]).to eq(recent.id)
    expect(got["rate"]).to eq("20.00")
    expect(old.reload).to be_persisted
  end

  it "cliente tem precedência sobre firma" do
    override!("firm", firm.id, %w[SP *], "15.00", Date.new(2026, 1, 1))
    override!("client", client.id, %w[SP *], "12.00", Date.new(2026, 1, 1))
    expect(described_class.new(date:, firm_id: firm.id, client_id: client.id).lookup("lk_table", %w[SP *])).to include("rate" => "12.00", "_source" => "client")
    expect(described_class.new(date:, firm_id: firm.id).lookup("lk_table", %w[SP *])).to include("rate" => "15.00", "_source" => "firm")
  end
end
