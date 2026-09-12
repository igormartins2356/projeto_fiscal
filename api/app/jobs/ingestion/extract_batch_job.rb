module Ingestion
  class ExtractBatchJob < ApplicationJob
    queue_as :ingestion
    discard_on ActiveRecord::RecordNotFound
    MAX_DEPTH = 3                     # pasta zipada > zip de nota cancelada > xml
    MAX_ENTRY_BYTES = 32.megabytes    # nenhum XML de NF-e chega perto disso
    MAX_TOTAL_BYTES = 512.megabytes   # zip bomb: total descompactado do lote

    def perform(batch_id)
      batch = Ingestion::UploadBatch.find(batch_id)
      # retry do Sidekiq não pode reenfileirar um lote já distribuído
      return unless batch.state.in?(%w[pending extracting])
      extract(batch)
    rescue ActiveRecord::RecordNotFound
      raise
    rescue StandardError => e
      Rails.logger.error("ExtractBatchJob #{batch_id}: #{e.class}: #{e.message}")
      batch&.update!(state: "failed", errors_log: batch.errors_log + [{ "file" => batch.original_filename, "error" => e.message }])
    end

    private

    def extract(batch)
      batch.update!(state: "extracting")
      path = Rails.root.join("storage", "uploads", batch.storage_ref)
      @bytes = 0
      @client = batch.client
      @storage = Ingestion::XmlStorage.new
      # cada entrada vai para o storage durante a varredura e só a referência fica na lista: acumular o
      # conteúdo até o fim mantinha centenas de MB de String vivas no worker num lote grande de XMLs
      # (o conteúdo também não cabe no Redis)
      refs = if batch.original_filename.to_s.downcase.end_with?(".zip")
        extract_zip(File.binread(path), batch.original_filename, 0)
      else
        [store_entry(batch.original_filename, File.binread(path))]
      end
      raise ArgumentError, "nenhum XML encontrado em #{batch.original_filename}" if refs.empty?
      # cancelamento/eventos por último: garante que a autorização exista antes de projetar o evento
      refs.sort_by! { |name, _| name.to_s.downcase.include?("cancelamento") || name.to_s.downcase.include?("evento") ? 1 : 0 }
      batch.update!(state: "parsing", files_total: refs.size)
      refs.each { |name, ref| Ingestion::ParseDocumentJob.perform_later(batch.id, name, ref) }
    end

    def store_entry(name, xml)
      [name, @storage.store(client: @client, hash: Digest::SHA256.hexdigest(xml), xml:, filename: name)]
    end

    def extract_zip(bytes, container_name, depth)
      raise ArgumentError, "zip aninhado além do limite em #{container_name}" if depth > MAX_DEPTH
      out = []
      Zip::File.open_buffer(StringIO.new(bytes)) do |z|
        z.each do |e|
          next unless e.file?
          name = "#{container_name}/#{e.name}"
          next unless e.name.downcase.end_with?(".zip", ".xml")
          raise ArgumentError, "#{name} descompactado passa de #{MAX_ENTRY_BYTES} bytes" if e.size > MAX_ENTRY_BYTES
          @bytes += e.size
          raise ArgumentError, "lote descompactado passa de #{MAX_TOTAL_BYTES} bytes" if @bytes > MAX_TOTAL_BYTES
          if e.name.downcase.end_with?(".zip")
            out.concat(extract_zip(e.get_input_stream.read, name, depth + 1))
          else
            out << store_entry(name, e.get_input_stream.read)
          end
        end
      end
      out
    end
  end
end
