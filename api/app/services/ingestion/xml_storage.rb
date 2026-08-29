module Ingestion
  # XML bruto imutável. Dev: disco local (storage/). Prod: S3 (trocar implementação, mesma interface).
  class XmlStorage
    def initialize(root: Rails.root.join("storage", "xml")) = @root = root

    def store(client:, hash:, xml:, filename: nil)
      dir = @root.join(client.id.to_s, hash[0, 2])
      FileUtils.mkdir_p(dir)
      path = dir.join("#{hash}.xml")
      File.write(path, xml) unless path.exist?
      path.relative_path_from(@root).to_s
    end

    def read(ref) = File.read(@root.join(ref))
  end
end
