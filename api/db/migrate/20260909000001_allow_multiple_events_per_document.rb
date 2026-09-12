class AllowMultipleEventsPerDocument < ActiveRecord::Migration[8.1]
  def change
    # Uma nota tem vários eventos com a mesma chNFe (carta de correção + cancelamento):
    # a unicidade por chave vale só para o documento em si, não para seus eventos.
    remove_index :documents, column: [:client_id, :access_key, :kind], unique: true, where: "access_key IS NOT NULL",
                 name: "index_documents_on_client_id_and_access_key_and_kind"
    add_index :documents, [:client_id, :access_key, :kind], unique: true,
              where: "access_key IS NOT NULL AND kind <> 'event'",
              name: "index_documents_on_client_id_and_access_key_and_kind"
    add_index :documents, [:client_id, :target_access_key]   # eventos pendentes da nota, por cliente

    add_column :upload_batches, :files_skipped, :integer, null: false, default: 0   # homologação / XML de terceiro
  end
end
