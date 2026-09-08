module Ingestion
  # Reexecuta as derivações do canônico (CANONICO.md §8) para documentos já importados —
  # usado após publicar/atualizar tabelas do Catalog. Preserva status projetado por eventos.
  class Rederive
    def self.call(scope)
      updated = 0
      scope.includes(:items).find_each do |doc|
        next unless doc.kind.in?(%w[nfe nfce])
        canonical = doc.data.merge("items" => doc.items.map(&:data))
        catalog = Catalog::Lookup.new(date: doc.reference_date || Date.current)
        Ingestion::Nfe::Derivations.call(canonical, monitored_cnpj: doc.data["monitored_cnpj"], catalog:)
        items = canonical.delete("items")
        doc.update_columns(data: canonical, operation_nature: canonical.dig("operation", "nature"), catalog_versions: catalog.versions_used)
        doc.items.each do |item|
          data = items.find { |i| i["number"] == item.number } or next
          item.update_columns(data:, icms_situation_code: data.dig("icms", "situation_code"))
        end
        updated += 1
      end
      updated
    end
  end
end
