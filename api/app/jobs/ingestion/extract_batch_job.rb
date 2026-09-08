module Ingestion
  class ExtractBatchJob < ApplicationJob
    queue_as :ingestion
    MAX_DEPTH = 3   # pasta zipada > zip de nota cancelada > xml

    def perform(batch_id)
      batch = Ingestion::UploadBatch.find(batch_id)
      batch.update!(state: "extracting")
      path = Rails.root.join("storage", "uploads", batch.storage_ref)
      entries = if batch.original_filename.to_s.downcase.end_with?(".zip")
        extract_zip(File.binread(path), batch.original_filename, 0)
      else
        [[batch.original_filename, File.read(path)]]
      end
      # cancelamento/eventos por último: garante que a autorização exista antes de projetar o evento
      entries.sort_by! { |name, _| name.to_s.downcase.include?("cancelamento") || name.to_s.downcase.include?("evento") ? 1 : 0 }
      batch.update!(state: "parsing", files_total: entries.size)
      entries.each { |name, xml| Ingestion::ParseDocumentJob.perform_later(batch.id, name, xml) }
    end

    private

    def extract_zip(bytes, container_name, depth)
      raise ArgumentError, "zip aninhado além do limite em #{container_name}" if depth > MAX_DEPTH
      out = []
      Zip::File.open_buffer(StringIO.new(bytes)) do |z|
        z.each do |e|
          next unless e.file?
          name = "#{container_name}/#{e.name}"
          if e.name.downcase.end_with?(".zip")
            out.concat(extract_zip(e.get_input_stream.read, name, depth + 1))
          elsif e.name.downcase.end_with?(".xml")
            out << [name, e.get_input_stream.read]
          end
        end
      end
      out
    end
  end
end
