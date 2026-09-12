firm = Accounts::Firm.find_or_create_by!(name: "Escritório Piloto") { |f| f.cnpj = "11111111000111" }
Accounts::User.find_or_create_by!(email: "admin@fiscal.local") do |u|
  # Senha pública só em development/test: um platform_admin com "password123" em produção seria porta aberta — lá exige SEED_ADMIN_PASSWORD.
  password = ENV["SEED_ADMIN_PASSWORD"].presence
  password ||= "password123" if Rails.env.development? || Rails.env.test?
  raise "SEED_ADMIN_PASSWORD obrigatório fora de development/test" unless password
  u.firm = firm; u.name = "Admin"; u.password = password; u.role = "platform_admin"
end
client = Accounts::Client.find_or_create_by!(firm:, cnpj: "12345678000190") do |c|
  c.legal_name = "Cliente Exemplo Ltda"; c.uf = "SP"; c.city_code = "3550308"
end
Scenario::TaxScenario.find_or_create_by!(client:, effective_from: Date.new(2024, 1, 1)) do |s|
  s.state = "published"
  s.data = { "tax_regime" => "simples_nacional", "uf" => "SP", "icms_taxpayer" => true, "ipi_taxpayer" => false,
             "activity" => ["commerce"], "sells_to_final_consumer" => true, "uses_nfce" => true,
             "st" => { "source" => "catalog", "overrides" => [] }, "benefits" => [], "pis_cofins" => { "regime" => "simples" } }
end
puts "accounts: firm=#{firm.id} client=#{client.id}"
