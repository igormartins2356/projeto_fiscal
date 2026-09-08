module Rules
  module Primitives
    # Eventos incoerentes: cancelamento fora do prazo, carta de correção em nota cancelada, cancelamento de nota com devolução referenciada.
    class EventConsistency < Base
      register "event_consistency"
      scope "cross_document"
      params_schema cancellation_deadline_hours: { default: 24 }, check: { default: "all" }
      vars :problem, :hours_after_issue

      def call
        docs = @ctx.dig("period", "documents") || []
        events = @ctx.dig("period", "events") || []
        by_key = docs.to_h { |d| [d["access_key"], d] }
        hits = []
        events.each do |ev|
          doc = by_key[ev["access_key"]] or next
          kind = ev.dig("event", "kind")
          if kind.in?(%w[cancellation cancellation_by_replacement]) && check?("late_cancellation")
            issued, occurred = Time.zone.parse(doc.dig("issuance", "issued_at").to_s), Time.zone.parse(ev.dig("event", "occurred_at").to_s)
            if issued && occurred && occurred > issued + @params["cancellation_deadline_hours"].to_i.hours
              hours = ((occurred - issued) / 3600).round
              hits << { target: { document_id: doc["_id"] }, evidence: { "problem" => "late_cancellation", "hours_after_issue" => hours, "issued_at" => doc.dig("issuance", "issued_at"), "cancelled_at" => ev.dig("event", "occurred_at") },
                        vars: { "problem" => "cancelamento #{hours}h após a emissão (prazo #{@params['cancellation_deadline_hours']}h)", "hours_after_issue" => hours } }
            end
          end
          if kind == "correction_letter" && doc.dig("status", "state") == "cancelled" && check?("correction_on_cancelled")
            hits << { target: { document_id: doc["_id"] }, evidence: { "problem" => "correction_on_cancelled", "occurred_at" => ev.dig("event", "occurred_at") },
                      vars: { "problem" => "carta de correção em nota cancelada" } }
          end
        end
        if check?("cancelled_with_return")
          docs.select { |d| d.dig("status", "state") == "cancelled" }.each do |cancelled|
            ret = docs.find { |d| d.dig("issuance", "purpose") == "return" && (d["references"] || []).any? { |r| r["access_key"] == cancelled["access_key"] } }
            next unless ret
            hits << { target: { document_id: ret["_id"] }, evidence: { "problem" => "return_of_cancelled", "cancelled_access_key" => cancelled["access_key"] },
                      vars: { "problem" => "devolução referencia nota cancelada #{cancelled['access_key']}" } }
          end
        end
        hits
      end

      private

      def check?(name) = @params["check"] == "all" || Array(@params["check"]).include?(name)
    end
  end
end
