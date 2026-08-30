module Ingestion
  # XML → Parser → Derivations → Document + DocumentItems. Idempotente por (client, xml_hash).
  class DocumentImporter
    Result = Struct.new(:document, :status, keyword_init: true) # status: created | duplicate | skipped

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
      return Result.new(status: :skipped) if canonical["environment"] == "homologation"

      if %w[nfe nfce].include?(canonical["kind"])
        return Result.new(status: :skipped) unless [canonical.dig("issuer", "cnpj"), canonical.dig("recipient", "cnpj")].include?(@client.cnpj)
        Nfe::Derivations.call(canonical, monitored_cnpj: @client.cnpj)
      end
      xml_ref = @storage.store(client: @client, hash:, xml:, filename:)
      doc = persist(canonical, xml_ref)
      apply_event(doc) if doc.kind == "event"
      Ingestion::ReferenceResolver.new(@client).call(doc)
      Result.new(document: doc, status: :created)
    end

    private

    def persist(c, xml_ref)
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
          target_access_key: (c["access_key"] if c["kind"] == "event"), data: c
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
