module Ingestion
  class ParseDocumentJob < ApplicationJob
    queue_as :ingestion
    discard_on ActiveRecord::RecordNotFound

    def perform(batch_id, filename, xml_ref)
      batch = Ingestion::UploadBatch.find(batch_id)
      result = Ingestion::DocumentImporter.new(client: batch.client, upload_batch: batch).call(Ingestion::XmlStorage.new.read(xml_ref), filename:)
      if result.status == :skipped
        # homologação / XML de terceiro: não é erro, mas o escritório precisa saber que a nota não entrou
        Ingestion::UploadBatch.where(id: batch_id).update_all(["files_skipped = files_skipped + 1, errors_log = errors_log || ?::jsonb", [{ file: filename, skipped: result.reason }].to_json])
        # XML recusado não vira `document`: sem apagar, ficaria guardado para sempre no diretório do cliente
        Ingestion::XmlStorage.new.delete(xml_ref) unless Ingestion::Document.exists?(client_id: batch.client_id, xml_ref:)
      else
        Ingestion::UploadBatch.where(id: batch_id).update_all("files_parsed = files_parsed + 1")
      end
    rescue ActiveRecord::RecordNotFound
      raise
    rescue StandardError => e
      Ingestion::UploadBatch.where(id: batch_id).update_all(["files_failed = files_failed + 1, errors_log = errors_log || ?::jsonb", [{ file: filename, error: e.message }].to_json])
    ensure
      batch&.reload
      batch.update!(state: "done") if batch && batch.files_parsed + batch.files_failed + batch.files_skipped >= batch.files_total
    end
  end
end
