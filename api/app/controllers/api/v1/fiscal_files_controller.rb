module Api
  module V1
    class FiscalFilesController < BaseController
      before_action :require_client!

      def index
        render json: current_client.fiscal_files.order(created_at: :desc).limit(50).map { |f| serialize(f) }
      end

      def show = render(json: serialize(current_client.fiscal_files.find(params[:id]), full: true))

      def create
        file = params.require(:file)
        if current_client.fiscal_files.exists?(file_hash: Digest::SHA256.hexdigest(file.read.tap { file.rewind }))
          return render json: { error: "este arquivo já foi enviado" }, status: :unprocessable_entity
        end
        ref = "#{current_client.id}/sped/#{SecureRandom.uuid}.txt"
        path = Rails.root.join("storage", "uploads", ref)
        FileUtils.mkdir_p(path.dirname)
        File.binwrite(path, file.read)
        Ingestion::ParseFiscalFileJob.perform_later(current_client.id, ref, current_user.id)
        audit!("fiscal_file_uploaded", metadata: { ref: })
        head :accepted
      end

      private

      def serialize(f, full: false)
        h = f.as_json(only: %i[id kind layout_version purpose period_start period_end state records_count created_at])
        h[:summary] = f.summary.slice("c100", "linked_documents")
        h[:errors_count] = f.errors_log.size
        h[:errors_log] = f.errors_log.first(50) if full
        h
      end
    end
  end
end
