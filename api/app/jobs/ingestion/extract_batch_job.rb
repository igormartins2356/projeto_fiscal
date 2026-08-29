module Ingestion
  class ExtractBatchJob < ApplicationJob
    queue_as :ingestion

    def perform(batch_id)
      batch = Ingestion::UploadBatch.find(batch_id)
      batch.update!(state: "extracting")
      path = Rails.root.join("storage", "uploads", batch.storage_ref)
      entries = if batch.original_filename.to_s.downcase.end_with?(".zip")
        Zip::File.open(path) { |z| z.filter_map { |e| [e.name, e.get_input_stream.read] if e.file? && e.name.downcase.end_with?(".xml") } }
      else
        [[batch.original_filename, File.read(path)]]
      end
      batch.update!(state: "parsing", files_total: entries.size)
      entries.each { |name, xml| Ingestion::ParseDocumentJob.perform_later(batch.id, name, xml) }
    end
  end
end
