module Ingestion
  # XML → Parser → Derivations → Document + DocumentItems. Idempotente por (client, xml_hash).
  class DocumentImporter
    Result = Struct.new(:document, :status, :reason, keyword_init: true) # status: created | duplicate | skipped (reason em pt-BR)

    def initialize(client:, upload_batch: nil, storage: Ingestion::XmlStorage.new)
      @client = client
      @batch = upload_batch
      @storage = storage
    end

    def call(xml, filename: nil)
      hash = Digest::SHA256.hexdigest(xml)
      if (existing = Ingestion::Document.find_by(client_id: @client.id, xml_hash: hash))
        return Result.new(document: existing, status: :duplicate)
      end
      canonical = Nfe::Parser.call(xml)
      case canonical["environment"]
      when "homologation" then return Result.new(status: :skipped, reason: "XML de homologação (tpAmb=2): não tem valor fiscal")
      when nil then return Result.new(status: :skipped, reason: "ambiente (tpAmb) ausente no XML: não dá para saber se é documento de produção")
      end

      catalog = nil
      if %w[nfe nfce].include?(canonical["kind"])
        unless [canonical.dig("issuer", "cnpj"), canonical.dig("recipient", "cnpj")].include?(@client.cnpj)
          return Result.new(status: :skipped, reason: "documento de terceiro: o CNPJ do cliente não é emitente nem destinatário")
        end
        # versões do catálogo usadas na derivação ficam gravadas no documento (CANONICO §8)
        catalog = Catalog::Lookup.new(date: Date.parse(Nfe::Derivations.reference_date!(canonical)))
        Nfe::Derivations.call(canonical, monitored_cnpj: @client.cnpj, catalog:)
      end
      xml_ref = @storage.store(client: @client, hash:, xml:, filename:)
      doc = persist(canonical, xml_ref, catalog)
      apply_event(doc) if doc.kind == "event"
      apply_pending_events(doc) if %w[nfe nfce].include?(doc.kind)
      Ingestion::ReferenceResolver.new(@client).call(doc)
      Result.new(document: doc, status: :created)
    rescue ActiveRecord::RecordNotUnique
      # corrida entre dois jobs do mesmo lote: o primeiro gravou, este é duplicata.
      # O mesmo evento reenviado com formatação diferente tem outro xml_hash, então é preciso
      # procurá-lo pela identidade do evento (chave + tipo + sequência), que é o índice violado.
      existing = Ingestion::Document.find_by(client_id: @client.id, xml_hash: hash) || existing_event(canonical)
      raise unless existing
      Result.new(document: existing, status: :duplicate)
    end

    private

    # Identidade do evento no canônico: a mesma nota pode receber vários eventos, mas não o mesmo
    # evento duas vezes (índice único por chave + tipo + sequência).
    def existing_event(canonical)
      return nil unless canonical["kind"] == "event"
      Ingestion::Document.where(client_id: @client.id, access_key: canonical["access_key"], kind: "event")
                         .where("data -> 'event' ->> 'code' = ? AND data -> 'event' ->> 'sequence' = ?",
                                canonical.dig("event", "code").to_s, canonical.dig("event", "sequence").to_s).first
    end

    def persist(c, xml_ref, catalog = nil)
      items = c.delete("items") || []
      Ingestion::Document.transaction do
        doc = Ingestion::Document.create!(
          firm_id: @client.firm_id, client: @client, upload_batch: @batch,
          kind: c["kind"], model: c["model"], access_key: c["access_key"], xml_hash: c["xml_hash"], xml_ref:,
          layout_version: c["layout_version"], role: c["role"], reference_date: c["reference_date"], period: c["period"],
          issued_at: c.dig("issuance", "issued_at"), series: c.dig("issuance", "series"), number: c.dig("issuance", "number"),
          issuer_cnpj: c.dig("issuer", "cnpj"), recipient_cnpj: c.dig("recipient", "cnpj"),
          direction: c.dig("operation", "direction"), operation_nature: c.dig("operation", "nature"),
          status_state: c.dig("status", "state"), total_amount: c.dig("totals", "total"),
          target_access_key: (c["access_key"] if c["kind"] == "event"), catalog_versions: catalog&.versions_used || {}, data: c
        )
        rows = items.map do |i|
          { document_id: doc.id, client_id: @client.id, number: i["number"], product_code: i.dig("product", "code"), ncm: i.dig("product", "ncm"),
            cest: i.dig("product", "cest"), cfop: i.dig("product", "cfop"), icms_situation_code: i.dig("icms", "situation_code"),
            pis_cst: i.dig("pis", "cst"), cofins_cst: i.dig("cofins", "cst"), ipi_cst: i.dig("ipi", "cst"),
            ibs_cbs_cst: i.dig("ibs_cbs", "cst"), ibs_cbs_class_code: i.dig("ibs_cbs", "class_code"),
            net_amount: i["net_amount"], icms_base_amount: i.dig("icms", "base_amount"), icms_amount: i.dig("icms", "amount"),
            icms_st_amount: i.dig("icms_st", "amount"), data: i }
        end
        Ingestion::DocumentItem.insert_all!(rows) if rows.any?
        doc
      end
    end

    # Autorização importada depois do cancelamento: aplica eventos que já esperavam por ela
    def apply_pending_events(doc)
      Ingestion::Document.where(client_id: @client.id, kind: "event", target_access_key: doc.access_key).find_each { |ev| apply_event(ev) }
    end

    # Evento de cancelamento projeta status na nota alvo (CANONICO.md §8.6)
    def apply_event(event)
      kind = event.data.dig("event", "kind")
      return unless %w[cancellation cancellation_by_replacement].include?(kind) && event.data.dig("protocol", "status_code").in?(%w[135 155])
      target = Ingestion::Document.find_by(client_id: @client.id, access_key: event.target_access_key, kind: %w[nfe nfce]) or return
      data = target.data
      data["status"] = (data["status"] || {}).merge("state" => "cancelled", "cancelled_at" => event.data.dig("event", "occurred_at"))
      target.update!(status_state: "cancelled", data:)
    end
  end
end
