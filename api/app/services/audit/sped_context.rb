module Audit
  # Contexto do arquivo SPED para as primitivas de cross-check: C100 com filhos, info do cabeçalho e erros estruturais do parse.
  module SpedContext
    def self.build(file)
      children = file.records.where(record_type: %w[C170 C190 C101]).order(:line_number).group_by(&:parent_id)
      c100 = file.records.where(record_type: "C100").order(:line_number).map do |r|
        kids = (children[r.id] || []).group_by(&:record_type)
        { "record_id" => r.id, "line" => r.line_number, "fields" => r.fields, "access_key" => r.document_access_key, "document_id" => r.document_id,
          "c170" => (kids["C170"] || []).map { |k| { "record_id" => k.id, "line" => k.line_number, "fields" => k.fields } },
          "c190" => (kids["C190"] || []).map { |k| { "record_id" => k.id, "line" => k.line_number, "fields" => k.fields } } }
      end
      { "info" => file.as_json(only: %i[id kind layout_version purpose period_start period_end records_count]).merge("errors" => file.errors_log, "summary" => file.summary),
        "c100" => c100 }
    end
  end
end
