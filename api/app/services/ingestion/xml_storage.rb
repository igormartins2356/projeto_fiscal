module Ingestion
  # XML bruto imutável. Dev: disco local (storage/). Prod: S3 (trocar implementação, mesma interface).
  class XmlStorage
    def initialize(root: Rails.root.join("storage", "xml")) = @root = root

    def store(client:, hash:, xml:, filename: nil)
      dir = @root.join(client.id.to_s, hash[0, 2])
      FileUtils.mkdir_p(dir)
      path = dir.join("#{hash}.xml")
      File.binwrite(path, xml) unless path.exist?
      path.relative_path_from(@root).to_s
    end

    # Só para XML recusado na importação (homologação, documento de terceiro), que não vira `document`.
    def delete(ref)
      path = @root.join(ref)
      File.delete(path) if path.to_s.start_with?(@root.to_s) && File.exist?(path)
    end

    def read(ref) = File.binread(@root.join(ref))   # XML de ERP costuma vir em ISO-8859-1; quem decide a codificação é o parser
  end
end
