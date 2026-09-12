class TightenReferenceRowAndFiscalRecordIntegrity < ActiveRecord::Migration[8.1]
  def up
    # Base com dados legados aceita os dois casos que este arquivo passa a proibir: sem limpar antes, o
    # CREATE UNIQUE INDEX e o ADD FOREIGN KEY abortam e travam o deploy.
    execute <<~SQL
      DELETE FROM reference_rows r USING reference_rows k
      WHERE r.reference_version_id = k.reference_version_id AND r.key = k.key
        AND r.effective_from IS NOT DISTINCT FROM k.effective_from AND r.id > k.id
    SQL
    execute "UPDATE fiscal_records SET parent_id = NULL WHERE parent_id IS NOT NULL AND parent_id NOT IN (SELECT id FROM fiscal_records)"

    # Duas linhas com a mesma chave E a mesma vigência na mesma versão deixavam o lookup com "a última vence"
    # (Catalog::Lookup monta um Hash por chave). Chave repetida com vigências DIFERENTES continua legítima:
    # é a alíquota que muda no meio da vigência da versão (DATA_SOURCES §5). NULLS NOT DISTINCT porque a
    # maioria das linhas não tem vigência própria e dois NULL têm de colidir.
    remove_index :reference_rows, column: %i[reference_version_id key],
                 name: "index_reference_rows_on_reference_version_id_and_key"
    add_index :reference_rows, %i[reference_version_id key effective_from], unique: true, nulls_not_distinct: true,
              name: "index_reference_rows_on_version_key_and_effective_from"

    # hierarquia do SPED (C100 → C170) não tinha integridade nem índice: apagar um registro pai deixava filho órfão
    add_index :fiscal_records, :parent_id
    add_foreign_key :fiscal_records, :fiscal_records, column: :parent_id, on_delete: :cascade
  end

  def down
    remove_foreign_key :fiscal_records, :fiscal_records, column: :parent_id
    remove_index :fiscal_records, :parent_id
    remove_index :reference_rows, name: "index_reference_rows_on_version_key_and_effective_from"
    add_index :reference_rows, %i[reference_version_id key], name: "index_reference_rows_on_reference_version_id_and_key"
  end
end
