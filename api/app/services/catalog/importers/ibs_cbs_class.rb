require "net/http"

module Catalog
  module Importers
    # Tabela cClassTrib × CST IBS/CBS (classe A). Fontes, em ordem:
    # 1) JSON já extraído (upload/arquivo) — aceita o formato da API (lista plana) ou o `dadosOriginais` da página pública
    # 2) Página pública da SVRS (sem certificado): extrai `var dadosOriginais = [...]`
    class IbsCbsClass
      PAGE = "https://dfe-portal.svrs.rs.gov.br/DFE/ClassificacaoTributaria"
      # Início do regime IBS/CBS (período de teste): LC 214/2025, arts. 343 e 348.
      LC_214_EFFECTIVE_FROM = Date.new(2026, 1, 1)
      # Toda cClassTrib nasce da LC 214/2025; a SVRS informa o artigo por linha (TexUrlLegislacao) e nem sempre o preenche.
      LC_214_LEGAL_BASIS = "LC 214/2025"

      def initialize(table = Catalog::ReferenceTable.find_or_create_by!(code: "ibs_cbs_class") { |t| t.name = "Classificação tributária IBS/CBS (cClassTrib)"; t.key_names = ["class_code"]; t.key_arity = 1; t.source_class = "A"; t.source_url = PAGE })
        @table = table
      end

      def call(json: nil, user: nil)
        payload = json || fetch_page
        rows = payload.first.is_a?(Hash) && payload.first.key?("ClassificacoesTributarias") ? parse_grouped(payload) : parse_flat(payload)
        last = @table.versions.order(version: :desc).first
        version = @table.versions.create!(version: (last&.version || 0) + 1, effective_from: [rows.filter_map { |r| r[:effective_from] }.min, LC_214_EFFECTIVE_FROM].compact.min,
                                          state: "draft", source_url: json ? "upload" : PAGE, imported_by: user, notes: "#{rows.size} classificações (formato SVRS)")
        Catalog::ReferenceRow.insert_all!(rows.map { |r| r.merge(reference_version_id: version.id) }) if rows.any?
        { version:, imported: rows.size }
      end

      private

      # Formato da página/agrupado: [{Cst:, NomeCst:, Ind..., ClassificacoesTributarias: [{CodClassTrib:, ...}]}]
      def parse_grouped(data)
        data.flat_map do |cst_group|
          Array(cst_group["ClassificacoesTributarias"]).map do |k|
            basis = k["TexUrlLegislacao"].to_s.presence || LC_214_LEGAL_BASIS
            { key: [k["CodClassTrib"].to_s.rjust(6, "0")],
              data: { "cst" => cst_group["Cst"].to_s.rjust(3, "0"), "cst_name" => cst_group["NomeCst"],
                      "description" => k["NomeClassTrib"].to_s.strip, "short_name" => k["NomeReduzido"],
                      "reduction_ibs_pct" => k["PercRedIbs"]&.to_s, "reduction_cbs_pct" => k["PercRedCbs"]&.to_s,
                      "indicators" => { "nfe" => k["IndNfe"], "nfce" => k["IndNfce"], "cte" => k["IndCte"], "nfse" => k["IndNfse"],
                                        "trib_regular" => k["IndTribRegular"], "cred_pres" => k["IndPermiteCredPres"], "mono_retem" => k["IndMonoRetem"] }.compact,
                      "annex" => k["NroAnexo"], "legal_basis" => basis },
              effective_from: parse_date(k["DthIniVig"]), effective_until: parse_date(k["DthFimVig"]),
              legal_basis: basis }
          end
        end
      end

      def parse_flat(list)
        list.map do |e|
          e = e.to_h.transform_keys { |x| x.to_s.downcase }
          code = (e["cclasstrib"] || e["codclasstrib"] || e["codigo"] || e["code"]).to_s.rjust(6, "0")
          basis = (e["texurllegislacao"] || e["legislacao"] || e["baselegal"]).to_s.presence || LC_214_LEGAL_BASIS
          { key: [code], data: { "cst" => (e["cst"] || "").to_s.rjust(3, "0"), "description" => (e["nomeclasstrib"] || e["descricao"] || e["description"]).to_s.strip,
                                 "reduction_ibs_pct" => (e["percredibs"] || e["predaliq"])&.to_s, "reduction_cbs_pct" => e["percredcbs"]&.to_s, "legal_basis" => basis },
            effective_from: parse_date(e["dthinivig"] || e["datainicio"]), effective_until: parse_date(e["dthfimvig"] || e["datafim"]), legal_basis: basis }
        end
      end

      def fetch_page
        uri = URI(PAGE)
        res = Net::HTTP.get_response(uri, { "User-Agent" => "Mozilla/5.0" })
        raise ArgumentError, "SVRS respondeu #{res.code}" unless res.is_a?(Net::HTTPSuccess)
        body = res.body.force_encoding("UTF-8")
        start = body.index("var dadosOriginais = ") or raise ArgumentError, "página da SVRS sem dadosOriginais (layout mudou?)"
        start += "var dadosOriginais = ".length
        depth = 0
        finish = start
        body[start..].each_char.with_index do |ch, i|
          depth += 1 if ch == "["
          depth -= 1 if ch == "]"
          if depth.zero? && ch == "]"
            finish = start + i + 1
            break
          end
        end
        JSON.parse(body[start...finish])
      end

      def parse_date(v)
        return nil if v.blank?
        Date.parse(v.to_s[0, 10])
      rescue ArgumentError
        nil
      end
    end
  end
end
