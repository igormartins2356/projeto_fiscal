module Ingestion
  class ParseFiscalFileJob < ApplicationJob
    queue_as :ingestion

    def perform(client_id, storage_ref, uploaded_by_id = nil)
      client = Accounts::Client.find(client_id)
      content = File.binread(Rails.root.join("storage", "uploads", storage_ref))
      Ingestion::Sped::Parser.call(content, client:, storage_ref:, uploaded_by: uploaded_by_id && Accounts::User.find_by(id: uploaded_by_id))
    rescue Ingestion::Sped::Parser::InvalidFile => e
      Ingestion::FiscalFile.create!(firm_id: client.firm_id, client:, kind: "sped_icms_ipi", storage_ref:, file_hash: Digest::SHA256.hexdigest(content.to_s),
                                    state: "failed", errors_log: [{ "line" => 0, "error" => e.message }])
    end
  end
end
