module Api
  module V1
    class FiscalFilesController < BaseController
      before_action :require_client!
      MAX_UPLOAD_BYTES = 300.megabytes
      ALLOWED_EXTENSIONS = %w[.txt].freeze

      def index
        rows, meta = paginate(current_client.fiscal_files.order(created_at: :desc))
        render json: meta.merge(data: rows.map { |f| serialize(f) })
      end

      def show = render(json: serialize(current_client.fiscal_files.find(params[:id]), full: true))

      def create
        file = params[:file]
        return render json: { error: "arquivo inválido" }, status: :unprocessable_entity unless file.is_a?(ActionDispatch::Http::UploadedFile)
        filename = File.basename(file.original_filename.to_s.delete("\0"))
        return render json: { error: "extensão não aceita (envie .txt)" }, status: :unprocessable_entity unless ALLOWED_EXTENSIONS.include?(File.extname(filename).downcase)
        return render json: { error: "tamanho acima do limite de #{MAX_UPLOAD_BYTES / 1.megabyte} MB" }, status: :unprocessable_entity if file.size.to_i > MAX_UPLOAD_BYTES
        # Hash e cópia direto do arquivo temporário: `file.read` trazia até 300 MB para a memória do processo web,
        # duas vezes (uma para o SHA-256, outra para gravar).
        if current_client.fiscal_files.exists?(file_hash: Digest::SHA256.file(file.tempfile.path).hexdigest)
          return render json: { error: "este arquivo já foi enviado" }, status: :unprocessable_entity
        end
        ref = "#{current_client.id}/sped/#{SecureRandom.uuid}.txt"
        path = Rails.root.join("storage", "uploads", ref)
        FileUtils.mkdir_p(path.dirname)
        FileUtils.cp(file.tempfile.path, path)
        Ingestion::ParseFiscalFileJob.perform_later(current_client.id, ref, current_user.id)
        audit!("fiscal_file_uploaded", ref:, filename:, bytes: file.size)
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
