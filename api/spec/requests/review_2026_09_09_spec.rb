require "rails_helper"

# Achados da revisão em sessão cega de 2026-09-09 (lote de controllers/config).
RSpec.describe "Revisão 2026-09-09", type: :request do
  let(:firm) { Accounts::Firm.create!(name: "Firma") }
  let!(:admin) { Accounts::User.create!(firm:, name: "Ana", email: "ana@x.com", password: "senha-forte-123", role: "platform_admin") }

  def login(email = "ana@x.com", password = "senha-forte-123")
    post "/api/v1/auth/login", params: { email:, password: }, as: :json
    response.parsed_body
  end

  def auth(token) = { "Authorization" => "Bearer #{token}" }

  describe "[1] enumeração de contas pelo status HTTP" do
    it "responde o mesmo status para e-mail existente e inexistente quando falta a senha" do
      post "/api/v1/auth/login", params: { email: "ana@x.com" }, as: :json
      existente = response.status
      post "/api/v1/auth/login", params: { email: "nao-existe@x.com" }, as: :json
      inexistente = response.status
      expect(existente).to eq(inexistente)
      expect(existente).to eq(400)
    end
  end

  describe "[13] custo de bcrypt na conta bloqueada" do
    it "gasta o mesmo bcrypt quando a conta está bloqueada" do
      admin.update_columns(failed_attempts: Accounts::User::MAX_FAILED, locked_until: 10.minutes.from_now)
      expect(BCrypt::Password).to receive(:new).at_least(:once).and_call_original
      login("ana@x.com", "senha-forte-123")
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "[2] access token sobrevive à troca de senha" do
    let!(:bia) { Accounts::User.create!(firm:, name: "Bia", email: "bia@x.com", password: "outra-senha-123", role: "accountant") }

    it "recusa o access token emitido antes do reset de senha pelo administrador" do
      vitima = login("bia@x.com", "outra-senha-123")["access_token"]
      get "/api/v1/auth/me", headers: auth(vitima)
      expect(response).to have_http_status(:ok)

      patch "/api/v1/users/#{bia.id}", params: { password: "nova-senha-do-admin" }, as: :json, headers: auth(login["access_token"])
      expect(response).to have_http_status(:ok)

      get "/api/v1/auth/me", headers: auth(vitima)
      expect(response).to have_http_status(:unauthorized)
    end

    it "aceita o access token emitido depois da troca" do
      patch "/api/v1/users/#{bia.id}", params: { password: "nova-senha-do-admin" }, as: :json, headers: auth(login["access_token"])
      novo = login("bia@x.com", "nova-senha-do-admin")["access_token"]
      get "/api/v1/auth/me", headers: auth(novo)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "[3] publicação retroativa de versão de tabela" do
    let(:table) { Catalog::ReferenceTable.create!(code: "rev_table", name: "Alíquota", key_arity: 2, key_names: %w[uf ncm]) }
    let!(:v1) do
      v = table.versions.create!(version: 1, effective_from: Date.new(2026, 1, 1), state: "published", published_at: Time.current)
      Catalog::ReferenceRow.insert_all!([{ reference_version_id: v.id, key: %w[SP *], data: { "rate" => "18.00" }, legal_basis: "RICMS/SP" }])
      v
    end

    it "fecha a vigência da nova versão na véspera da já publicada (backfill)" do
      v2 = table.versions.create!(version: 2, effective_from: Date.new(2025, 1, 1), state: "draft")
      Catalog::ReferenceRow.insert_all!([{ reference_version_id: v2.id, key: %w[SP *], data: { "rate" => "12.00" }, legal_basis: "RICMS/SP" }])
      post "/api/v1/admin/reference_tables/#{table.id}/versions/#{v2.id}/publish", headers: auth(login["access_token"])
      expect(response).to have_http_status(:ok), response.body

      expect(v2.reload.effective_until).to eq(Date.new(2025, 12, 31))
      expect(table.version_effective_on(Date.new(2026, 6, 1))).to eq(v1)
      expect(Catalog::Lookup.new(date: Date.new(2026, 6, 1)).lookup("rev_table", %w[SP *])["rate"]).to eq("18.00")
      expect(Catalog::Lookup.new(date: Date.new(2025, 6, 1)).lookup("rev_table", %w[SP *])["rate"]).to eq("12.00")
    end
  end

  describe "[4] rederivação ao publicar versão de tabela" do
    let(:table) { Catalog::ReferenceTable.create!(code: "rev_table", name: "Alíquota", key_arity: 2, key_names: %w[uf ncm]) }
    let!(:v1) do
      v = table.versions.create!(version: 1, effective_from: Date.new(2026, 1, 1), state: "published", published_at: Time.current)
      Catalog::ReferenceRow.insert_all!([{ reference_version_id: v.id, key: %w[SP *], data: { "rate" => "18.00" }, legal_basis: "RICMS/SP" }])
      v
    end
    let!(:meu) { Accounts::Client.create!(firm:, cnpj: "12345678000190", legal_name: "C", uf: "SP") }
    let!(:alheio) do
      outra = Accounts::Firm.create!(name: "Outra firma")
      Accounts::Client.create!(firm: outra, cnpj: "98765432000155", legal_name: "Alheio", uf: "MG")
    end

    around do |ex|
      old = ActiveJob::Base.queue_adapter
      ActiveJob::Base.queue_adapter = :test
      ex.run
    ensure
      ActiveJob::Base.queue_adapter = old
    end

    it "enfileira um único job orquestrador, com o período de vigência da versão" do
      v2 = table.versions.create!(version: 2, effective_from: Date.new(2026, 7, 1), state: "draft")
      Catalog::ReferenceRow.insert_all!([{ reference_version_id: v2.id, key: %w[SP *], data: { "rate" => "20.00" }, legal_basis: "RICMS/SP" }])

      expect { post "/api/v1/admin/reference_tables/#{table.id}/versions/#{v2.id}/publish", headers: auth(login["access_token"]) }
        .to have_enqueued_job(Ingestion::RederiveJob).with(nil, period_start: Date.new(2026, 7, 1), period_end: nil).exactly(:once)
      expect(response).to have_http_status(:ok), response.body
      expect(meu).to be_present
      expect(alheio).to be_present
    end
  end

  describe "[5] autorização por prefixo de caminho no índice de tabelas" do
    let!(:contador) { Accounts::User.create!(firm:, name: "Ivo", email: "ivo@x.com", password: "senha-forte-123", role: "accountant") }
    let!(:table) { Catalog::ReferenceTable.create!(code: "rev_table", name: "Alíquota", key_arity: 2, key_names: %w[uf ncm], source_url: "https://interno") }

    it "não deixa um accountant listar o índice administrativo forjando o marcador da rota pública" do
      h = auth(login("ivo@x.com", "senha-forte-123")["access_token"])
      get "/api/v1/admin/reference_tables", headers: h, params: { public_listing: true }
      expect(response).to have_http_status(:forbidden)
    end

    it "não abre o índice administrativo quando a app é montada sob um prefixo (SCRIPT_NAME)" do
      h = auth(login("ivo@x.com", "senha-forte-123")["access_token"])
      get "/api/v1/admin/reference_tables", headers: h, env: { "SCRIPT_NAME" => "/fiscal" }
      expect(response).to have_http_status(:forbidden)
    end

    it "mantém a rota pública aberta e sem os campos internos da tabela" do
      h = auth(login("ivo@x.com", "senha-forte-123")["access_token"])
      get "/api/v1/reference_tables", headers: h
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.first.keys).to contain_exactly("id", "code", "name", "key_arity", "key_names", "current_version")
    end
  end

  describe "[6] sobreposição de regra" do
    let!(:accountant_firm) { firm }
    let!(:client) { Accounts::Client.create!(firm:, cnpj: "12345678000190", legal_name: "C", uf: "SP") }
    let!(:rule) do
      Rules::Rule.create!(code: "TEST.REV.RULE", version: 1, title: "t", scope: "item", severity: "error", state: "published", effective_from: Date.new(2020, 1, 1),
                          body: { "assert" => { "field" => "item.icms.cst", "op" => "present" }, "message" => "CST ausente" })
    end
    let(:h) { auth(login["access_token"]) }

    it "não deixa virar replace de cliente por PATCH" do
      o = Rules::RuleOverride.create!(rule_code: rule.code, source_type: "client", source_id: client.id, override_action: "adjust",
                                      patch: { "severity" => "warning" }, effective_from: Date.new(2026, 1, 1), justification: "j", created_by: admin)
      patch "/api/v1/rule_overrides/#{o.id}", headers: h, as: :json,
            params: { override_action: "replace", patch: { assert: { field: "item.icms.cst", op: "eq", value: "00" }, message: "m" } }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(o.reload.override_action).to eq("adjust")
    end

    it "valida o replace com o mesmo escopo que o Resolver executa" do
      post "/api/v1/rule_overrides", headers: h, as: :json,
           params: { rule_code: rule.code, source_type: "firm", source_id: firm.id, override_action: "replace", effective_from: "2026-01-01", justification: "j",
                     patch: { scope: "period", assert: { field: "period.documents", op: "present" }, message: "m" } }
      # `scope` do patch não vale: o Resolver força o scope da regra (item), e `period.*` não existe no escopo item.
      expect(response).to have_http_status(:unprocessable_entity), response.body
      expect(response.parsed_body["errors"].join).to include("period")
    end

    it "valida contra a regra que o motor usa, não contra um draft mais novo" do
      Rules::Rule.create!(code: rule.code, version: 2, title: "t", scope: "period", severity: "error", state: "draft", effective_from: Date.new(2020, 1, 1),
                          body: { "assert" => { "field" => "period.documents", "op" => "present" }, "message" => "m" })
      post "/api/v1/rule_overrides", headers: h, as: :json,
           params: { rule_code: rule.code, source_type: "firm", source_id: firm.id, override_action: "adjust", effective_from: "2026-01-01", justification: "j",
                     patch: { assert: { field: "period.documents", op: "present" } } }
      expect(response).to have_http_status(:unprocessable_entity), response.body
    end
  end

  describe "[7] aridade da chave em reference_row_overrides" do
    let!(:table) { Catalog::ReferenceTable.create!(code: "rev_table", name: "Alíquota", key_arity: 2, key_names: %w[uf ncm]) }

    it "recusa PATCH que grava chave com aridade errada" do
      o = Catalog::ReferenceRowOverride.create!(reference_table: table, source_type: "firm", source_id: firm.id, key: %w[SP *],
                                                data: { "rate" => "12.00" }, effective_from: Date.new(2026, 1, 1), justification: "j", created_by: admin)
      patch "/api/v1/reference_row_overrides/#{o.id}", headers: auth(login["access_token"]), as: :json, params: { key: ["SP"] }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(o.reload.key).to eq(%w[SP *])
    end
  end

  describe "[8] upload de arquivo fiscal sem ler tudo na memória" do
    let!(:client) { Accounts::Client.create!(firm:, cnpj: "12345678000190", legal_name: "C", uf: "SP") }

    it "não chama UploadedFile#read (leitura integral) ao gravar o arquivo" do
      file = Rack::Test::UploadedFile.new(StringIO.new("|0000|conteudo|\n"), "text/plain", original_filename: "sped.txt")
      allow_any_instance_of(ActionDispatch::Http::UploadedFile).to receive(:read).and_raise("leu o arquivo inteiro na memória")
      post "/api/v1/fiscal_files", params: { file: }, headers: auth(login["access_token"]).merge("X-Client-Id" => client.id.to_s)
      expect(response).to have_http_status(:accepted), response.body
    ensure
      FileUtils.rm_rf(Rails.root.join("storage", "uploads", client.id.to_s))
    end
  end

  describe "[15] listagem de runs" do
    let!(:client) { Accounts::Client.create!(firm:, cnpj: "12345678000190", legal_name: "C", uf: "SP") }

    it "não serializa os jsonb grandes (snapshot, coverage, evaluation_errors) em toda página" do
      client.audit_runs.create!(firm_id: firm.id, period_start: "2026-07-01", period_end: "2026-07-31",
                                snapshot: { "rules" => Array.new(50) { |i| "R#{i}" } }, coverage: { "st_uf" => [] }, evaluation_errors: [])
      get "/api/v1/audit_runs", headers: auth(login["access_token"]).merge("X-Client-Id" => client.id.to_s)
      expect(response).to have_http_status(:ok)
      row = response.parsed_body["data"].first
      expect(row.keys).not_to include("snapshot", "coverage", "evaluation_errors")
      expect(row).to include("id", "state", "documents_count", "findings_count", "period_start")
    end
  end

  describe "[11] unicidade do evento" do
    let!(:client) { Accounts::Client.create!(firm:, cnpj: "12345678000190", legal_name: "C", uf: "SP", city_code: "3550308") }

    it "não grava um segundo documento para o mesmo evento reenviado com formatação diferente" do
      xml = nfe_fixture("event_110111_cancellation")
      importer = Ingestion::DocumentImporter.new(client:)
      expect(importer.call(xml).status).to eq(:created)
      # mesmo tpEvento/nSeqEvento da mesma chNFe, só um espaço a mais: outro xml_hash, mesmo evento
      # O índice único garante a integridade; o importer traduz a violação em :duplicate, para o lote do
      # contador não acusar falha com mensagem crua do Postgres.
      expect(importer.call(xml.sub("<cOrgao>35</cOrgao>", "<cOrgao>35</cOrgao> ")).status).to eq(:duplicate)
      expect(Ingestion::Document.where(client_id: client.id, kind: "event").count).to eq(1)
    ensure
      FileUtils.rm_rf(Rails.root.join("storage", "xml", client.id.to_s))
    end
  end

  describe "[9] expurgo de arquivos e sobreposições ao excluir cliente" do
    let!(:client) { Accounts::Client.create!(firm:, cnpj: "12345678000190", legal_name: "C", uf: "SP") }
    let!(:table) { Catalog::ReferenceTable.create!(code: "rev_table", name: "Alíquota", key_arity: 2, key_names: %w[uf ncm]) }

    it "apaga os XML em disco e as sobreposições do cliente" do
      dir = Rails.root.join("storage", "xml", client.id.to_s)
      uploads = Rails.root.join("storage", "uploads", client.id.to_s)
      FileUtils.mkdir_p(dir.join("ab"))
      FileUtils.mkdir_p(uploads)
      File.write(dir.join("ab", "nota.xml"), "<nfe/>")
      File.write(uploads.join("sped.txt"), "|0000|")
      Rules::RuleOverride.create!(rule_code: "X.Y.Z", source_type: "client", source_id: client.id, override_action: "disable",
                                  effective_from: Date.new(2026, 1, 1), justification: "j", created_by: admin)
      Catalog::ReferenceRowOverride.create!(reference_table: table, source_type: "client", source_id: client.id, key: %w[SP *],
                                            data: { "rate" => "1" }, effective_from: Date.new(2026, 1, 1), justification: "j", created_by: admin)

      client.destroy!

      expect(Dir.exist?(dir)).to be false
      expect(Dir.exist?(uploads)).to be false
      expect(Rules::RuleOverride.where(source_type: "client", source_id: client.id).count).to eq(0)
      expect(Catalog::ReferenceRowOverride.where(source_type: "client", source_id: client.id).count).to eq(0)
    ensure
      FileUtils.rm_rf(Rails.root.join("storage", "xml", client.id.to_s))
      FileUtils.rm_rf(Rails.root.join("storage", "uploads", client.id.to_s))
    end
  end
  # A marca de troca de senha invalida todo access token anterior. Quem troca a PRÓPRIA senha não pode
  # ser expulso da tela por isso: o endpoint devolve uma sessão nova.
  describe "troca da própria senha" do
    let(:firm) { Accounts::Firm.create!(name: "Escritório PW") }
    let!(:user) { Accounts::User.create!(firm:, name: "Rita", email: "rita@x.com", password: "senha-forte-123", role: "accountant") }

    it "devolve uma sessão nova e o token antigo deixa de valer" do
      post "/api/v1/auth/login", params: { email: "rita@x.com", password: "senha-forte-123" }, as: :json
      old_token = response.parsed_body["access_token"]

      post "/api/v1/users/change_password", params: { current_password: "senha-forte-123", password: "outrasenha-1234" },
                                            headers: { "Authorization" => "Bearer #{old_token}" }, as: :json
      expect(response).to have_http_status(:ok), response.body
      fresh = response.parsed_body
      expect(fresh["access_token"]).to be_present
      expect(fresh["refresh_token"]).to be_present

      get "/api/v1/auth/me", headers: { "Authorization" => "Bearer #{fresh['access_token']}" }
      expect(response).to have_http_status(:ok)

      get "/api/v1/auth/me", headers: { "Authorization" => "Bearer #{old_token}" }
      expect(response).to have_http_status(:unauthorized)
    end

    # O require_role!("firm_admin") do controller valia para TODAS as actions, inclusive esta.
    it "permite que um accountant troque a própria senha" do
      post "/api/v1/auth/login", params: { email: "rita@x.com", password: "senha-forte-123" }, as: :json
      token = response.parsed_body["access_token"]
      post "/api/v1/users/change_password", params: { current_password: "senha-forte-123", password: "outrasenha-1234" },
                                            headers: { "Authorization" => "Bearer #{token}" }, as: :json
      expect(response).to have_http_status(:ok), response.body
      expect(user.reload.authenticate("outrasenha-1234")).to be_truthy
    end
  end

end
