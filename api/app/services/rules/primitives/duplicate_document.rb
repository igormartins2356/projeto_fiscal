module Rules
  module Primitives
    class DuplicateDocument < Base
      register "duplicate_document"
      scope "cross_document"
      params_schema match_on: { default: "number_series_cnpj" }, only_authorized: { default: true }

      def call
        docs = @ctx.dig("period", "documents") || []
        docs = docs.select { |d| d.dig("status", "state") == "authorized" } if @params["only_authorized"]
        groups = docs.group_by do |d|
          case @params["match_on"]
          when "access_key" then d["access_key"]
          else [d.dig("issuer", "cnpj"), d["model"], d.dig("issuance", "series"), d.dig("issuance", "number")]
          end
        end
        groups.filter_map do |_k, group|
          keys = group.map { |d| d["access_key"] }.uniq
          next if keys.size < 2
          first = group.first
          { target: { document_id: first["_id"] },
            evidence: { "access_keys" => keys, "number" => first.dig("issuance", "number"), "series" => first.dig("issuance", "series") },
            vars: { "access_keys" => keys, "issuance" => first["issuance"] } }
        end
      end
    end
  end
end
