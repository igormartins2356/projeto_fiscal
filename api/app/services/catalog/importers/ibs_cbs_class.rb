require "net/http"
require "openssl"

module Catalog
  module Importers
    # Tabela cClassTrib × CST IBS/CBS (classe A). Fonte: API SVRS (certificado ICP-Brasil, env SVRS_CERT_P12/SVRS_CERT_PASSWORD)
    # ou arquivo JSON baixado do portal (upload). Tolerante a variações de nome de campo entre versões do IT.
    class IbsCbsClass
      API = "https://cff.svrs.rs.gov.br/api/v1/consultas/classTrib"

      def initialize(table = Catalog::ReferenceTable.find_or_create_by!(code: "ibs_cbs_class") { |t| t.name = "Classificação tributária IBS/CBS (cClassTrib)"; t.key_names = ["class_code"]; t.key_arity = 1; t.source_class = "A"; t.source_url = API })
        @table = table
      end

      def call(json: nil, user: nil)
        payload = json || fetch_api
        list = payload.is_a?(Array) ? payload : (payload["data"] || payload["classTrib"] || payload["items"] || payload.values.find { |v| v.is_a?(Array) } || [])
        rows = list.filter_map do |e|
          e = e.to_h.transform_keys { |k| k.to_s.downcase }
          code = (e["cclasstrib"] || e["codigo"] || e["code"]).to_s.rjust(6, "0")
          next if code.blank? || code == "000000" && e["cclasstrib"].nil?
          cst = (e["cst"] || e["cstibscbs"] || e["cst_ibs_cbs"]).to_s.rjust(3, "0")
          { key: [code], data: { "cst" => cst, "description" => (e["descricao"] || e["description"] || e["nome"]).to_s.strip, "reduction_pct" => (e["predaliq"] || e["percentualreducao"] || e["reduction_pct"])&.to_s,
                                "indicators" => e.slice("indop", "indnfe", "indnfce", "indcte", "indnfse", "indpresenca").compact, "legal_basis" => (e["baselegal"] || e["fundamentacaolegal"] || e["legal_basis"]).to_s.presence },
            effective_from: parse_date(e["datainicio"] || e["vigenciainicio"] || e["effective_from"]), effective_until: parse_date(e["datafim"] || e["vigenciafim"] || e["effective_until"]),
            legal_basis: (e["baselegal"] || e["fundamentacaolegal"]).to_s.presence }
        end
        last = @table.versions.order(version: :desc).first
        version = @table.versions.create!(version: (last&.version || 0) + 1, effective_from: [rows.filter_map { |r| r[:effective_from] }.min, Date.new(2026, 1, 1)].compact.min, state: "draft", source_url: json ? "upload" : API, imported_by: user, notes: "#{rows.size} classificações")
        Catalog::ReferenceRow.insert_all!(rows.map { |r| r.merge(reference_version_id: version.id) }) if rows.any?
        { version:, imported: rows.size }
      end

      private

      def fetch_api
        p12_path, password = ENV["SVRS_CERT_P12"], ENV["SVRS_CERT_PASSWORD"]
        raise ArgumentError, "SVRS_CERT_P12 não configurado; envie o JSON baixado do portal" if p12_path.blank?
        p12 = OpenSSL::PKCS12.new(File.binread(p12_path), password)
        uri = URI(API)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.cert = p12.certificate
        http.key = p12.key
        res = http.get(uri.request_uri, { "Accept" => "application/json" })
        raise ArgumentError, "SVRS respondeu #{res.code}" unless res.is_a?(Net::HTTPSuccess)
        JSON.parse(res.body)
      end

      def parse_date(v)
        return nil if v.blank?
        v.to_s.include?("/") ? Date.strptime(v.to_s[0, 10], "%d/%m/%Y") : Date.parse(v.to_s[0, 10])
      rescue ArgumentError
        nil
      end
    end
  end
end
