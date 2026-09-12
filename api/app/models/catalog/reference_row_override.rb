module Catalog
  class ReferenceRowOverride < ApplicationRecord
    belongs_to :reference_table, class_name: "Catalog::ReferenceTable"
    belongs_to :created_by, class_name: "Accounts::User"
    validates :source_type, inclusion: { in: %w[firm client] }
    validates :justification, presence: true
    validates :effective_from, presence: true
    validate :effective_until_after_effective_from
    validate :no_overlapping_period
    validate :key_arity_matches_table

    private

    # Chave com aridade diferente da tabela nunca casa no Catalog::Lookup (indexado por [code, key]):
    # o contador vê a sobreposição gravada e o motor segue com a tabela da plataforma, sem erro nenhum.
    # No model porque o controller só validava no create — um PATCH gravava a chave errada.
    def key_arity_matches_table
      return if reference_table.nil?
      errors.add(:key, "deve ter #{reference_table.key_arity} parte(s)") if Array(key).size != reference_table.key_arity
    end

    def effective_until_after_effective_from
      return if effective_from.blank? || effective_until.blank?
      errors.add(:effective_until, "deve ser igual ou posterior ao início da vigência") if effective_until < effective_from
    end

    # Duas sobreposições vigentes na mesma data para a mesma (tabela, origem, chave) tornam o lookup arbitrário:
    # a vigência anterior precisa ser encerrada antes de valer a nova.
    def no_overlapping_period
      return if effective_from.blank? || reference_table_id.blank? || key.blank?
      scope = self.class.where(reference_table_id:, source_type:, source_id:, key:)
      scope = scope.where.not(id:) if persisted?
      scope = scope.where("effective_from <= ? AND (effective_until IS NULL OR effective_until >= ?)", effective_until || Date.new(9999, 12, 31), effective_from)
      return unless scope.exists?
      errors.add(:effective_from, "sobrepõe a vigência de outra sobreposição para a mesma chave (encerre a anterior)")
    end
  end
end
