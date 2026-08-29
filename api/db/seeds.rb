# Seed de desenvolvimento: firma, usuário, cliente, cenário, tabelas mínimas do Catalog e regras iniciais.
Dir[Rails.root.join("db/seeds/*.rb")].sort.each { |f| load f }
