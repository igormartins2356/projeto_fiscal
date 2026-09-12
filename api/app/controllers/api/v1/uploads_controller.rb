module Api
  module V1
    class UploadsController < BaseController
      before_action :require_client!
      MAX_UPLOAD_BYTES = 200.megabytes
      ALLOWED_EXTENSIONS = %w[.zip .xml].freeze
      SERIALIZED = %i[id state original_filename files_total files_parsed files_failed files_skipped errors_log created_at].freeze

      def create
        file = params[:file]
        return render json: { error: "arquivo inválido" }, status: :unprocessable_entity unless file.is_a?(ActionDispatch::Http::UploadedFile)
        filename = sanitize_filename(file.original_filename)
        ext = File.extname(filename).downcase
        return render json: { error: "extensão não aceita (envie #{ALLOWED_EXTENSIONS.join(' ou ')})" }, status: :unprocessable_entity unless ALLOWED_EXTENSIONS.include?(ext)
        return render json: { error: "tamanho acima do limite de #{MAX_UPLOAD_BYTES / 1.megabyte} MB" }, status: :unprocessable_entity if file.size.to_i > MAX_UPLOAD_BYTES

        ref = "#{current_client.id}/#{SecureRandom.uuid}#{ext}"
        path = Rails.root.join("storage", "uploads", ref)
        FileUtils.mkdir_p(path.dirname)
        File.binwrite(path, file.read)
        batch = Ingestion::UploadBatch.create!(firm_id: current_client.firm_id, client: current_client, user: current_user, original_filename: filename, storage_ref: ref)
        Ingestion::ExtractBatchJob.perform_later(batch.id)
        audit!("upload_created", subject: batch, filename:, bytes: file.size)
        render json: serialize(batch), status: :created
      end

      def show
        render json: serialize(Ingestion::UploadBatch.where(client: current_client).find(params[:id]))
      end

      private

      # storage_ref é caminho interno: não sai na API.
      def serialize(batch) = batch.as_json(only: SERIALIZED)

      # Nome vem do cliente: sem diretório e sem byte nulo (que quebra File.extname).
      def sanitize_filename(name) = File.basename(name.to_s.delete("\0")).strip
    end
  end
end
