module Catalog
  class ReferenceRow < ApplicationRecord
    belongs_to :reference_version, class_name: "Catalog::ReferenceVersion"

    # Linha de versão publicada é imutável: findings e audit_runs.snapshot apontam para ela.
    # Alterar exige nova versão (DATA_SOURCES §3.2).
    def readonly? = reference_version&.state.present? && reference_version.state != "draft"
  end
end
