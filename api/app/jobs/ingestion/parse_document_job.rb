module Ingestion
  class ParseDocumentJob < ApplicationJob
    queue_as :ingestion

    def perform(batch_id, filename, xml)
      batch = Ingestion::UploadBatch.find(batch_id)
      Ingestion::DocumentImporter.new(client: batch.client, upload_batch: batch).call(xml, filename:)
      Ingestion::UploadBatch.where(id: batch.id).update_all("files_parsed = files_parsed + 1")
    rescue => e
      Ingestion::UploadBatch.where(id: batch.id).update_all(["files_failed = files_failed + 1, errors_log = errors_log || ?::jsonb", [{ file: filename, error: e.message }].to_json])
    ensure
      batch.reload
      batch.update!(state: "done") if batch.files_parsed + batch.files_failed >= batch.files_total
    end
  end
end
