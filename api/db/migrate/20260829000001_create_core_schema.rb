class CreateCoreSchema < ActiveRecord::Migration[8.1]
  def change
    enable_extension "pgcrypto" unless extension_enabled?("pgcrypto")

    # ---------------------------------------------------------------- Accounts
    create_table :firms do |t|
      t.string  :name, null: false
      t.string  :cnpj, limit: 14
      t.jsonb   :settings, null: false, default: {}
      t.timestamps
    end

    create_table :users do |t|
      t.references :firm, null: false, foreign_key: true
      t.string  :email, null: false
      t.string  :name, null: false
      t.string  :password_digest, null: false
      t.string  :role, null: false, default: "accountant"   # platform_admin | firm_admin | accountant
      t.datetime :last_sign_in_at
      t.timestamps
    end
    add_index :users, :email, unique: true

    create_table :clients do |t|
      t.references :firm, null: false, foreign_key: true
      t.string  :cnpj, null: false, limit: 14
      t.string  :legal_name, null: false
      t.string  :trade_name
      t.string  :uf, null: false, limit: 2
      t.string  :city_code, limit: 7
      t.string  :ie
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :clients, [:firm_id, :cnpj], unique: true

    # ---------------------------------------------------------------- Scenario
    create_table :tax_scenarios do |t|
      t.references :client, null: false, foreign_key: true
      t.date    :effective_from, null: false
      t.date    :effective_until
      t.jsonb   :data, null: false, default: {}          # ver DSL_RULES.md §7
      t.jsonb   :field_origins, null: false, default: {} # {campo: inferred|manual}
      t.string  :state, null: false, default: "draft"    # draft | published
      t.references :created_by, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_index :tax_scenarios, [:client_id, :effective_from]

    # ---------------------------------------------------------------- Catalog
    create_table :reference_tables do |t|
      t.string  :code, null: false                        # ncm, cfop, cest, st_uf, icms_internal_rate...
      t.string  :name, null: false
      t.integer :key_arity, null: false, default: 1
      t.jsonb   :key_names, null: false, default: []
      t.jsonb   :row_schema, null: false, default: {}
      t.string  :source_class, null: false, default: "C"  # A | B | C | D (DATA_SOURCES.md)
      t.string  :source_url
      t.date    :next_review_on
      t.timestamps
    end
    add_index :reference_tables, :code, unique: true

    create_table :reference_versions do |t|
      t.references :reference_table, null: false, foreign_key: true
      t.integer :version, null: false
      t.date    :effective_from, null: false
      t.date    :effective_until
      t.string  :state, null: false, default: "draft"    # draft | published | retired
      t.string  :source_url
      t.string  :source_document_ref
      t.text    :notes
      t.references :imported_by, foreign_key: { to_table: :users }
      t.datetime :published_at
      t.timestamps
    end
    add_index :reference_versions, [:reference_table_id, :version], unique: true
    add_index :reference_versions, [:reference_table_id, :effective_from]

    create_table :reference_rows do |t|
      t.references :reference_version, null: false, foreign_key: true
      t.string  :key, array: true, null: false, default: []
      t.jsonb   :data, null: false, default: {}
      t.date    :effective_from
      t.date    :effective_until
      t.string  :legal_basis
    end
    add_index :reference_rows, [:reference_version_id, :key], using: :btree
    add_index :reference_rows, :key, using: :gin

    create_table :reference_row_overrides do |t|
      t.references :reference_table, null: false, foreign_key: true
      t.string  :source_type, null: false                  # firm | client
      t.bigint  :source_id, null: false
      t.string  :key, array: true, null: false, default: []
      t.jsonb   :data, null: false, default: {}
      t.date    :effective_from, null: false
      t.date    :effective_until
      t.string  :legal_basis
      t.text    :justification, null: false
      t.references :created_by, null: false, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_index :reference_row_overrides, [:reference_table_id, :source_type, :source_id, :key], name: "idx_ref_row_overrides_lookup"

    # ---------------------------------------------------------------- Rules
    create_table :rules do |t|                              # cada linha = uma versão de um code
      t.string  :code, null: false
      t.integer :version, null: false, default: 1
      t.integer :dsl_version, null: false, default: 1
      t.string  :title, null: false
      t.string  :scope, null: false                          # item | document | cross_document | period | scenario
      t.date    :effective_from, null: false
      t.date    :effective_until
      t.jsonb   :body, null: false, default: {}              # let/applies_when/assert/primitive/params/message... (DSL_RULES.md §1)
      t.string  :severity, null: false, default: "error"
      t.string  :state, null: false, default: "draft"        # draft | testing | shadow | published | retired
      t.string  :source_type, null: false, default: "platform" # platform | firm
      t.bigint  :source_id
      t.string  :tags, array: true, null: false, default: []
      t.references :created_by, foreign_key: { to_table: :users }
      t.datetime :published_at
      t.timestamps
    end
    add_index :rules, [:code, :version], unique: true
    add_index :rules, [:state, :effective_from]
    add_index :rules, :tags, using: :gin

    create_table :rule_overrides do |t|
      t.string  :rule_code, null: false
      t.string  :source_type, null: false                    # firm | client
      t.bigint  :source_id, null: false
      t.string  :action, null: false                         # disable | enable | adjust | replace
      t.jsonb   :patch, null: false, default: {}
      t.date    :effective_from, null: false
      t.date    :effective_until
      t.text    :justification, null: false
      t.references :created_by, null: false, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_index :rule_overrides, [:rule_code, :source_type, :source_id]

    create_table :rule_test_cases do |t|
      t.references :rule, null: false, foreign_key: true
      t.string  :name, null: false
      t.date    :reference_date, null: false
      t.jsonb   :scenario, null: false, default: {}
      t.jsonb   :input, null: false, default: {}
      t.jsonb   :catalog, null: false, default: {}
      t.jsonb   :expect, null: false, default: {}
      t.string  :last_result                                  # passed | failed
      t.datetime :last_run_at
      t.timestamps
    end

    # ---------------------------------------------------------------- Ingestion
    create_table :upload_batches do |t|
      t.references :firm, null: false, foreign_key: true
      t.references :client, null: false, foreign_key: true
      t.references :user, foreign_key: true
      t.string  :state, null: false, default: "pending"      # pending | extracting | parsing | done | failed
      t.string  :original_filename
      t.string  :storage_ref
      t.integer :files_total, null: false, default: 0
      t.integer :files_parsed, null: false, default: 0
      t.integer :files_failed, null: false, default: 0
      t.jsonb   :errors_log, null: false, default: []
      t.timestamps
    end

    create_table :documents do |t|
      t.references :firm, null: false, foreign_key: true
      t.references :client, null: false, foreign_key: true
      t.references :upload_batch, foreign_key: true
      t.string  :kind, null: false                            # nfe | nfce | event | invalidation
      t.string  :model, limit: 2
      t.string  :access_key, limit: 44
      t.string  :xml_hash, null: false, limit: 64
      t.string  :xml_ref, null: false
      t.string  :layout_version
      t.integer :schema_version, null: false, default: 1
      t.string  :role                                         # issuer | recipient | third_party
      t.date    :reference_date
      t.string  :period, limit: 7
      t.datetime :issued_at
      t.string  :series
      t.integer :number
      t.string  :issuer_cnpj, limit: 14
      t.string  :recipient_cnpj, limit: 14
      t.string  :direction                                    # inbound | outbound
      t.string  :operation_nature
      t.string  :status_state                                 # authorized | cancelled | denied | rejected | no_protocol
      t.decimal :total_amount, precision: 15, scale: 2
      t.jsonb   :data, null: false, default: {}               # documento canônico completo
      t.jsonb   :catalog_versions, null: false, default: {}
      t.string  :target_access_key, limit: 44                 # eventos: chave da nota alvo
      t.timestamps
    end
    add_index :documents, [:client_id, :access_key, :kind], unique: true, where: "access_key IS NOT NULL"
    add_index :documents, [:client_id, :xml_hash], unique: true
    add_index :documents, [:client_id, :reference_date]
    add_index :documents, [:client_id, :period]
    add_index :documents, [:client_id, :issuer_cnpj, :series, :number]
    add_index :documents, :target_access_key

    create_table :document_items do |t|
      t.references :document, null: false, foreign_key: true
      t.references :client, null: false, foreign_key: true
      t.integer :number, null: false
      t.string  :product_code
      t.string  :ncm, limit: 8
      t.string  :cest, limit: 7
      t.string  :cfop, limit: 4
      t.string  :icms_situation_code
      t.string  :pis_cst, limit: 2
      t.string  :cofins_cst, limit: 2
      t.string  :ipi_cst, limit: 2
      t.string  :ibs_cbs_cst, limit: 3
      t.string  :ibs_cbs_class_code, limit: 6
      t.decimal :net_amount, precision: 15, scale: 2
      t.decimal :icms_base_amount, precision: 15, scale: 2
      t.decimal :icms_amount, precision: 15, scale: 2
      t.decimal :icms_st_amount, precision: 15, scale: 2
      t.jsonb   :data, null: false, default: {}               # item canônico completo
    end
    add_index :document_items, [:document_id, :number], unique: true
    add_index :document_items, [:client_id, :ncm]
    add_index :document_items, [:client_id, :cfop]

    create_table :fiscal_files do |t|
      t.references :firm, null: false, foreign_key: true
      t.references :client, null: false, foreign_key: true
      t.references :upload_batch, foreign_key: true
      t.string  :kind, null: false                            # sped_icms_ipi | sintegra
      t.string  :layout_version
      t.date    :period_start
      t.date    :period_end
      t.string  :purpose                                      # original | rectifying
      t.string  :file_hash, null: false, limit: 64
      t.string  :storage_ref, null: false
      t.string  :state, null: false, default: "pending"
      t.integer :records_count, null: false, default: 0
      t.timestamps
    end
    add_index :fiscal_files, [:client_id, :file_hash], unique: true

    create_table :fiscal_records do |t|
      t.references :fiscal_file, null: false, foreign_key: true
      t.integer :line_number, null: false
      t.string  :block, limit: 1
      t.string  :record_type, null: false, limit: 4
      t.bigint  :parent_id
      t.string  :document_access_key, limit: 44
      t.references :document, foreign_key: true
      t.integer :item_number
      t.jsonb   :fields, null: false, default: {}
    end
    add_index :fiscal_records, [:fiscal_file_id, :record_type]
    add_index :fiscal_records, :document_access_key

    # ---------------------------------------------------------------- Audit
    create_table :audit_runs do |t|
      t.references :firm, null: false, foreign_key: true
      t.references :client, null: false, foreign_key: true
      t.references :triggered_by, foreign_key: { to_table: :users }
      t.date    :period_start, null: false
      t.date    :period_end, null: false
      t.string  :state, null: false, default: "queued"       # queued | running | done | failed
      t.jsonb   :snapshot, null: false, default: {}           # ids de versões usadas (DSL_RULES.md §9.3)
      t.integer :documents_count, null: false, default: 0
      t.integer :findings_count, null: false, default: 0
      t.jsonb   :evaluation_errors, null: false, default: []
      t.datetime :started_at
      t.datetime :finished_at
      t.timestamps
    end
    add_index :audit_runs, [:client_id, :created_at]

    create_table :findings do |t|
      t.references :audit_run, null: false, foreign_key: true
      t.references :client, null: false, foreign_key: true
      t.references :rule, null: false, foreign_key: true
      t.string  :rule_code, null: false
      t.string  :rule_source, null: false, default: "platform"
      t.references :document, foreign_key: true
      t.integer :item_number
      t.references :fiscal_record, foreign_key: true
      t.string  :scope, null: false
      t.string  :severity, null: false
      t.boolean :shadow, null: false, default: false
      t.text    :message, null: false
      t.jsonb   :evidence, null: false, default: {}
      t.string  :xml_path
      t.string  :group_key
      t.string  :dedupe_key, null: false
      t.string  :state, null: false, default: "open"          # open | justified | false_positive | fixed | ignored
      t.text    :state_note
      t.references :state_changed_by, foreign_key: { to_table: :users }
      t.datetime :state_changed_at
      t.timestamps
    end
    add_index :findings, [:audit_run_id, :dedupe_key], unique: true
    add_index :findings, [:client_id, :dedupe_key]
    add_index :findings, [:audit_run_id, :rule_code, :group_key]
    add_index :findings, [:document_id, :item_number]
  end
end
