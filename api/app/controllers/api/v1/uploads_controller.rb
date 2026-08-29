module Api
  module V1
    class UploadsController < BaseController
      def create
        file = params.require(:file)
        ref = "#{current_client.id}/#{SecureRandom.uuid}#{File.extname(file.original_filename)}"
        path = Rails.root.join("storage", "uploads", ref)
        FileUtils.mkdir_p(path.dirname)
        File.binwrite(path, file.read)
        batch = Ingestion::UploadBatch.create!(firm_id: current_client.firm_id, client: current_client, original_filename: file.original_filename, storage_ref: ref)
        Ingestion::ExtractBatchJob.perform_later(batch.id)
        render json: batch, status: :created
      end

      def show
        render json: Ingestion::UploadBatch.where(client: current_client).find(params[:id])
      end
    end
  end
end
