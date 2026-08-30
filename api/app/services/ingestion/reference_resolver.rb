module Ingestion
  # Resolve doc.references[].resolved/document_id dentro do cliente, nos dois sentidos (CANONICO.md §8.7).
  class ReferenceResolver
    def initialize(client) = @client = client

    # Chamado após importar `doc`
    def call(doc)
      resolve_outgoing(doc) if doc.kind.in?(%w[nfe nfce])
      resolve_incoming(doc) if doc.access_key.present?
    end

    private

    def resolve_outgoing(doc)
      refs = doc.data["references"] || []
      return if refs.empty?
      keys = refs.filter_map { |r| r["access_key"] }
      found = Ingestion::Document.where(client_id: @client.id, kind: %w[nfe nfce], access_key: keys).pluck(:access_key, :id).to_h
      changed = false
      refs.each do |r|
        id = found[r["access_key"]]
        next if r["resolved"] == !id.nil? && r["document_id"] == id
        r["resolved"] = !id.nil?
        r["document_id"] = id
        changed = true
      end
      doc.update_columns(data: doc.data) if changed
    end

    def resolve_incoming(doc)
      Ingestion::Document.where(client_id: @client.id, kind: %w[nfe nfce]).where("data->'references' @> ?", [{ access_key: doc.access_key }].to_json).find_each do |other|
        refs = other.data["references"]
        refs.each { |r| next unless r["access_key"] == doc.access_key; r["resolved"] = true; r["document_id"] = doc.id }
        other.update_columns(data: other.data)
      end
    end
  end
end
