module Ingestion
  class ParseFiscalFileJob < ApplicationJob
    queue_as :ingestion
    discard_on ActiveRecord::RecordNotFound

    def perform(client_id, storage_ref, uploaded_by_id = nil)
      client = Accounts::Client.find(client_id)
      content = File.binread(Rails.root.join("storage", "uploads", storage_ref))
      Ingestion::Sped::Parser.call(content, client:, storage_ref:, uploaded_by: uploaded_by_id && Accounts::User.find_by(id: uploaded_by_id))
    rescue Ingestion::Sped::Parser::InvalidFile => e
      # arquivo recusado antes de virar registro: fica o motivo em pt-BR na tela do escritório
      file = Ingestion::FiscalFile.find_or_initialize_by(client_id: client.id, file_hash: Digest::SHA256.hexdigest(content.to_s))
      file.assign_attributes(firm_id: client.firm_id, client:, kind: "sped_icms_ipi", storage_ref:, state: "failed",
                             errors_log: [{ "line" => 0, "error" => e.message }])
      file.save!
    end
  end
end
