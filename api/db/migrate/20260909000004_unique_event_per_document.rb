class UniqueEventPerDocument < ActiveRecord::Migration[8.1]
  # 20260909000001 tirou os eventos do índice único por (client_id, access_key, kind) e nada tomou o lugar:
  # sobrou a unicidade por xml_hash, que é dos bytes. O mesmo cancelamento reenviado com uma diferença de
  # formatação virava um segundo `document` e era aplicado de novo à nota. A identidade do evento é
  # (chNFe, tpEvento, nSeqEvento) — é ela que precisa ser única por cliente.
  INDEX = "index_documents_on_client_id_and_access_key_and_event"

  def up
    execute <<~SQL
      DELETE FROM documents d USING documents k
      WHERE d.kind = 'event' AND k.kind = 'event'
        AND d.client_id = k.client_id AND d.access_key = k.access_key
        AND coalesce(d.data->'event'->>'code', '') = coalesce(k.data->'event'->>'code', '')
        AND coalesce(d.data->'event'->>'sequence', '') = coalesce(k.data->'event'->>'sequence', '')
        AND d.id > k.id
    SQL
    execute <<~SQL
      CREATE UNIQUE INDEX #{INDEX} ON documents
        (client_id, access_key, kind, (coalesce(data->'event'->>'code', '')), (coalesce(data->'event'->>'sequence', '')))
        WHERE access_key IS NOT NULL AND kind = 'event'
    SQL
  end

  def down
    execute "DROP INDEX IF EXISTS #{INDEX}"
  end
end
