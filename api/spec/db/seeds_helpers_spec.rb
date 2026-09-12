require "rails_helper"

# Helpers de db/seeds/00_helpers.rb: retirada de regra e recarga de tabela num banco já semeado.
# O invariante em teste é "publicado é imutável": a seed fecha vigência e reescreve só a v1 que ela própria criou.
RSpec.describe "db/seeds/00_helpers" do
  before { load Rails.root.join("db/seeds/00_helpers.rb") }

  def seed_test_table!(rate)
    seed_table!("test_internal_rate", name: "Tabela de teste", key_names: ["uf"], source_class: "D",
                effective_from: Date.new(2024, 1, 1), rows: [[["SP"], { "rate" => rate }]])
  end

  def rows_of(version) = version.rows.order(:id).pluck(:key, :data)

  describe "retire_rule!" do
    let!(:rule) do
      Rules::Rule.create!(code: "TEST.RETIRE.RULE", version: 1, title: "Título publicado", scope: "item", severity: "error",
                          effective_from: Date.new(2020, 1, 1), state: "published", published_at: Time.current,
                          body: { "assert" => { "field" => "item.icms.rate", "op" => "present" }, "message" => "x" })
    end

    it "fecha a vigência na data informada e preserva o título da regra publicada" do
      retire_rule!("TEST.RETIRE.RULE", "substituída por outra regra", on: Date.new(2026, 8, 30))
      expect(rule.reload).to have_attributes(state: "retired", effective_until: Date.new(2026, 8, 30), title: "Título publicado")
    end
  end

  describe "seed_table! em banco já semeado" do
    it "reescreve a própria v1 em development/test quando a curadoria da seed muda" do
      seed_test_table!("18.00")
      version = Catalog::ReferenceTable.find_by!(code: "test_internal_rate").versions.find_by!(version: 1)
      expect { seed_test_table!("19.00") }.to output(/tabela test_internal_rate v1/).to_stderr
      expect(rows_of(version)).to eq([[["SP"], { "rate" => "19.00" }]])
    end

    it "não reescreve nada quando o conteúdo da seed é o mesmo" do
      seed_test_table!("18.00")
      version = Catalog::ReferenceTable.find_by!(code: "test_internal_rate").versions.find_by!(version: 1)
      expect { seed_test_table!("18.00") }.not_to output.to_stderr
      expect(version.reload.updated_at).to eq(version.updated_at)
      expect(rows_of(version)).to eq([[["SP"], { "rate" => "18.00" }]])
    end

    # v2 costuma ser importação manual pelo painel (icms_internal_rate: 27 UFs) e não está no repositório:
    # se a seed a reescrevesse, apagaria curadoria irrecuperável.
    it "não toca em versão que não é da seed (v2 importada pelo painel)" do
      seed_test_table!("18.00")
      table = Catalog::ReferenceTable.find_by!(code: "test_internal_rate")
      v2 = table.versions.create!(version: 2, effective_from: Date.new(2026, 1, 1), state: "published", published_at: Time.current, notes: "import manual pelo painel")
      Catalog::ReferenceRow.insert_all!([{ reference_version_id: v2.id, key: ["BA"], data: { "rate" => "20.50" } }])

      seed_test_table!("19.00")

      expect(rows_of(v2)).to eq([[["BA"], { "rate" => "20.50" }]])
      expect(rows_of(table.versions.find_by!(version: 1))).to eq([[["SP"], { "rate" => "18.00" }]])
    end
  end
end
