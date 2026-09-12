require "rails_helper"

# Seeds: idempotentes, sem escrever em versão/regra publicada, sem senha pública fora de development/test.
RSpec.describe "db/seeds" do
  def production!
    allow(Rails).to receive(:env).and_return(ActiveSupport::EnvironmentInquirer.new("production"))
  end

  def seed(file) = load Rails.root.join("db/seeds/#{file}.rb")

  def published_rows_snapshot(version_ids = Catalog::ReferenceVersion.published.pluck(:id))
    Catalog::ReferenceRow.where(reference_version_id: version_ids).order(:id).pluck(:id, :reference_version_id, :key, :data, :legal_basis)
  end

  context "carga repetida (banco já semeado)" do
    before { seed_all! }

    it "não altera regras nem versões/linhas publicadas na segunda carga" do
      rules = Rules::Rule.order(:id).pluck(:id, :version, :state, :published_at, :updated_at, :body)
      versions = Catalog::ReferenceVersion.order(:id).pluck(:id, :version, :state, :published_at, :updated_at)
      rows = published_rows_snapshot

      expect { seed_all! }.not_to output(/publicad/).to_stderr

      expect(Rules::Rule.order(:id).pluck(:id, :version, :state, :published_at, :updated_at, :body)).to eq(rules)
      expect(Catalog::ReferenceVersion.order(:id).pluck(:id, :version, :state, :published_at, :updated_at)).to eq(versions)
      expect(published_rows_snapshot).to eq(rows)
    end

    it "seed_rule! sobre regra publicada com definição diferente levanta fora de development/test" do
      rule = Rules::Rule.where(state: "published").find_by!(code: "ICMS.BASE.CALC")
      production!
      expect { seed_rule!(rule.code, version: rule.version, assert: { "field" => "item.icms.rate", "op" => "eq", "value" => "99.00" }) }
        .to raise_error(RuntimeError, "regra ICMS.BASE.CALC v#{rule.version} publicada: crie versão #{rule.version + 1}")
      expect(rule.reload.body["assert"]).not_to include("value" => "99.00")
    end

    it "seed_rule! com a mesma definição não levanta fora de development/test" do
      rule = Rules::Rule.where(state: "published").find_by!(code: "ICMS.BASE.CALC")
      same = rule.body.symbolize_keys.merge(version: rule.version, title: rule.title, scope: rule.scope, severity: rule.severity, effective_from: rule.effective_from)
      production!
      expect { seed_rule!(rule.code, **same) }.not_to raise_error
    end

    it "seed_rule! em development/test sobrescreve a regra publicada avisando (seeds são a fonte pré-go-live)" do
      rule = Rules::Rule.where(state: "published").find_by!(code: "ICMS.BASE.CALC")
      expect { seed_rule!(rule.code, version: rule.version, assert: { "field" => "item.icms.rate", "op" => "eq", "value" => "99.00" }) }
        .to output(/regra ICMS.BASE.CALC v1 publicada/).to_stderr
      expect(rule.reload.body["assert"]).to include("value" => "99.00")
      expect(rule.published_at).to be_present
    end

    it "seed_rows! recusa escrever em versão publicada fora de development/test" do
      version = Catalog::ReferenceTable.find_by!(code: "cfop").versions.published.first!
      production!
      expect { seed_rows!(version, [[["9999"], { "nature" => "other" }]]) }.to raise_error(RuntimeError, /tabela cfop v1 publicada/)
      expect(version.rows.where("key = ARRAY['9999']::varchar[]")).to be_empty
    end

    it "08_sped_layout não destrói versão publicada existente" do
      table = Catalog::ReferenceTable.find_by!(code: "sped_layout")
      ids = table.versions.published.pluck(:id)
      table.versions.update_all(notes: "v1 manual (banco antigo)")
      seed("08_sped_layout")
      expect(table.versions.pluck(:id)).to match_array(ids)
    end
  end

  context "primeira carga" do
    it "02b não cria nem altera linhas em versão publicada por 02" do
      seed("00_helpers"); seed("02_catalog")
      version_ids = Catalog::ReferenceVersion.published.pluck(:id)
      rows = published_rows_snapshot(version_ids)
      expect(rows).not_to be_empty
      seed("02b_catalog_extra")
      expect(published_rows_snapshot(version_ids)).to eq(rows)
    end

    it "cfop e cst_pis_cofins já nascem com os campos que a base de regras exige" do
      seed("00_helpers"); seed("02_catalog"); seed("02b_catalog_extra")
      lookup = Catalog::Lookup.new(date: Date.new(2026, 7, 1))
      expect(lookup.lookup("cfop", ["5405"])).to include("st_role" => "substituted", "st_related" => true, "requires_reference" => false, "own_production" => false)
      expect(lookup.lookup("cfop", ["5901"])).to include("nature" => "shipment", "direction" => "outbound")
      expect(lookup.lookup("cfop", ["5202"])).to include("requires_reference" => true)
      expect(lookup.lookup("cst_pis_cofins", ["01"])).to include("direction" => "outbound")
      expect(lookup.lookup("cst_pis_cofins", ["50"])).to include("direction" => "inbound")
      expect(lookup.lookup("icms_internal_rate", %w[MG *])).to include("fcp_rate" => "0.00")
    end

    it "seed_table! publica a versão só depois de inserir as linhas" do
      seed("00_helpers"); seed("02_catalog")
      Catalog::ReferenceVersion.published.find_each do |v|
        expect(v.rows.count).to be > 0
        expect(v.published_at).to be >= v.created_at
      end
    end
  end

  context "01_accounts fora de development/test" do
    before { allow(ENV).to receive(:[]).and_call_original }

    it "sem SEED_ADMIN_PASSWORD levanta e não cria o admin" do
      allow(ENV).to receive(:[]).with("SEED_ADMIN_PASSWORD").and_return(nil)
      production!
      expect { seed("01_accounts") }.to raise_error(RuntimeError, "SEED_ADMIN_PASSWORD obrigatório fora de development/test")
      expect(Accounts::User.find_by(email: "admin@fiscal.local")).to be_nil
    end

    it "com SEED_ADMIN_PASSWORD cria o admin com essa senha" do
      allow(ENV).to receive(:[]).with("SEED_ADMIN_PASSWORD").and_return("s3nh4-forte!")
      production!
      seed("01_accounts")
      admin = Accounts::User.find_by!(email: "admin@fiscal.local")
      expect(admin.authenticate("s3nh4-forte!")).to be_truthy
      expect(admin.authenticate("password123")).to be_falsey
    end

    it "07 e 11 (clientes reais de teste) não rodam" do
      allow(ENV).to receive(:[]).with("SEED_ADMIN_PASSWORD").and_return("s3nh4-forte!")
      allow(ENV).to receive(:[]).with("SEED_TEST_CLIENTS").and_return("1")
      production!
      seed("01_accounts"); seed("07_client_boiron"); seed("11_client_dzenk")
      expect(Accounts::Client.where(cnpj: %w[07498711000420 66412974000190])).to be_empty
    end
  end

  context "01_accounts em development/test" do
    it "sem SEED_ADMIN_PASSWORD usa a senha de desenvolvimento e cria os clientes de teste sob pedido" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("SEED_TEST_CLIENTS").and_return("1")
      seed("01_accounts"); seed("07_client_boiron"); seed("11_client_dzenk")
      expect(Accounts::User.find_by!(email: "admin@fiscal.local").authenticate("password123")).to be_truthy
      expect(Accounts::Client.where(cnpj: %w[07498711000420 66412974000190]).count).to eq(2)
    end

    it "sem SEED_TEST_CLIENTS não recria os clientes reais de teste" do
      seed("01_accounts"); seed("07_client_boiron"); seed("11_client_dzenk")
      expect(Accounts::Client.where(cnpj: %w[07498711000420 66412974000190])).to be_empty
    end
  end
end
