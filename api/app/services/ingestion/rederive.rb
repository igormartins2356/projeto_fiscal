module Ingestion
  # Reexecuta as derivações do canônico (CANONICO.md §8) para documentos já importados —
  # usado após publicar/atualizar tabelas do Catalog. Preserva status projetado por eventos.
  class Rederive
    def self.call(scope)
      updated = 0
      scope.includes(:items).find_each do |doc|
        next unless doc.kind.in?(%w[nfe nfce])
        canonical = doc.data.merge("items" => doc.items.map(&:data))
        begin
          # a data vem do dhEmi rederivado: se a regra de data mudou, a vigência de tabela acompanha
          catalog = Catalog::Lookup.new(date: Date.parse(Ingestion::Nfe::Derivations.reference_date!(canonical)))
          Ingestion::Nfe::Derivations.call(canonical, monitored_cnpj: doc.data["monitored_cnpj"], catalog:)
        rescue Ingestion::Nfe::Parser::InvalidXml => e
          Rails.logger.warn("Rederive: documento #{doc.id} ignorado — #{e.message}")
          next
        end
        items = canonical.delete("items")
        doc.update_columns(data: canonical, operation_nature: canonical.dig("operation", "nature"),
                           reference_date: canonical["reference_date"], period: canonical["period"], catalog_versions: catalog.versions_used)
        doc.items.each do |item|
          data = items.find { |i| i["number"] == item.number } or next
          item.update_columns(data:, icms_situation_code: data.dig("icms", "situation_code"))
        end
        # referências resolvidas não podem "desresolver" na rederivação (CANONICO §8.7)
        Ingestion::ReferenceResolver.new(doc.client).call(doc)
        updated += 1
      end
      updated
    end
  end
end
