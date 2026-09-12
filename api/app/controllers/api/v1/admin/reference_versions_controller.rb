module Api
  module V1
    module Admin
      class ReferenceVersionsController < BaseController
        before_action :set_table
        before_action :set_version, only: %i[show update rows import publish retire diff]
        rescue_from Catalog::Importers::Generic::InvalidData do |e|
          render json: { error: e.message }, status: :unprocessable_entity
        end

        def show = render(json: serialize(@version))

        # Cria versão draft (opcionalmente copiando as linhas da versão anterior)
        def create
          last = @table.versions.order(version: :desc).first
          v = @table.versions.create!(version: (last&.version || 0) + 1, effective_from: params.require(:effective_from), effective_until: params[:effective_until],
                                      state: "draft", source_url: params[:source_url], notes: params[:notes], imported_by: current_user)
          if params[:copy_from_previous] && last
            Catalog::ReferenceRow.insert_all!(last.rows.map { |r| { reference_version_id: v.id, key: r.key, data: r.data, effective_from: r.effective_from, effective_until: r.effective_until, legal_basis: r.legal_basis } }) if last.rows.exists?
          end
          render json: serialize(v), status: :created
        end

        def update
          return render json: { error: "versão publicada não é editável" }, status: :unprocessable_entity unless @version.state == "draft"
          @version.update!(params.permit(:effective_from, :effective_until, :source_url, :notes))
          audit!("reference_version_updated", subject: @version, changes: @version.previous_changes.except("updated_at"))
          render json: serialize(@version)
        end

        def rows
          scope = @version.rows.order(:key)
          scope = scope.where("array_to_string(key, '|') ILIKE ?", "%#{Catalog::ReferenceRow.sanitize_sql_like(params[:q])}%") if params[:q].present?
          rows, meta = paginate(scope)
          render json: meta.merge(data: rows.map { |r| r.as_json(only: %i[id key data effective_from effective_until legal_basis]) })
        end

        # POST import: arquivo CSV (cabeçalho = key_names + colunas de data) ou JSON [{key:[], data:{}, legal_basis, effective_from, effective_until}]
        # mode: replace (padrão) | merge (upsert por chave)
        def import
          return render json: { error: "versão publicada não é editável" }, status: :unprocessable_entity unless @version.state == "draft"
          result = Catalog::Importers::Generic.new(@table, @version).call(file: params[:file], rows: params[:rows], mode: params.fetch(:mode, "replace"), legal_basis: params[:legal_basis])
          audit!("reference_version_imported", subject: @version, **result)
          render json: result.merge(version: serialize(@version))
        end

        def publish
          return render json: { error: "já publicada" }, status: :unprocessable_entity if @version.state == "published"
          return render json: { error: "versão sem linhas" }, status: :unprocessable_entity unless @version.rows.exists?
          # DATA_SOURCES §0: sem base legal, a linha não é publicada.
          without_basis = @version.rows.where(legal_basis: [nil, ""]).count
          return render json: { error: "#{without_basis} linha(s) sem base legal; informe `legal_basis` (por linha ou no import) antes de publicar" }, status: :unprocessable_entity if without_basis.positive?
          Catalog::ReferenceVersion.transaction do
            others = @table.versions.published.where.not(id: @version.id)
            others.where("effective_from <= ?", @version.effective_from).find_each { |prev| close_previous!(prev) }
            @version.update!(state: "published", published_at: Time.current, effective_until: closing_bound(others))
          end
          audit!("reference_version_published", subject: @version)
          # Derivados dependentes do catálogo ficam congelados na importação: sem rederivar, publicar a tabela não muda documento nenhum.
          # Um único job orquestrador: percorrer os clientes dentro do request enfileirava N jobs e reprocessava
          # o histórico inteiro de todas as firmas — a rederivação vale só para o período de vigência desta versão.
          Ingestion::RederiveJob.perform_later(nil, period_start: @version.effective_from, period_end: @version.effective_until)
          render json: serialize(@version)
        end

        def retire
          @version.update!(state: "retired", effective_until: @version.effective_until || Date.current)
          audit!("reference_version_retired", subject: @version, effective_until: @version.effective_until)
          render json: serialize(@version)
        end

        # POST sync: importadores classe A (ncm, ibs_cbs_class). Cria versão draft a partir da fonte (ou de JSON enviado).
        def sync
          importer = { "ncm" => Catalog::Importers::Ncm, "ibs_cbs_class" => Catalog::Importers::IbsCbsClass }[@table.code]
          return render json: { error: "tabela sem importador automático" }, status: :unprocessable_entity unless importer
          json = params[:file] ? JSON.parse(params[:file].read) : nil
          result = importer.new(@table).call(json:, user: current_user)
          audit!("reference_table_synced", subject: result[:version], imported: result[:imported])
          render json: { imported: result[:imported], version: serialize(result[:version]) }, status: :created
        rescue ArgumentError, JSON::ParserError => e
          render json: { error: e.message }, status: :unprocessable_entity
        end

        # Diff contra a versão anterior: adicionadas, removidas, alteradas (amostra)
        def diff
          prev = @table.versions.where("version < ?", @version.version).order(version: :desc).first
          return render json: { previous: nil, added: [], removed: [], changed: [] } unless prev
          a = row_payloads(prev)
          b = row_payloads(@version)
          added = (b.keys - a.keys)
          removed = (a.keys - b.keys)
          changed = (a.keys & b.keys).select { |k| a[k] != b[k] }
          render json: { previous: prev.slice(:id, :version), counts: { added: added.size, removed: removed.size, changed: changed.size, unchanged: (a.keys & b.keys).size - changed.size },
                         added: added.first(200).map { |k| { key: k.first }.merge(b[k]) }, removed: removed.first(200).map { |k| { key: k.first }.merge(a[k]) },
                         changed: changed.first(200).map { |k| { key: k.first, before: a[k], after: b[k] } } }
        end

        private

        # Vigência e base legal da linha fazem parte do conteúdo: encerrar a vigência de um NCM não muda `data` nenhuma
        # e sairia do diff como "sem mudança".
        # A mesma chave pode ter mais de uma linha na versão, com vigências diferentes (DATA_SOURCES §67):
        # indexar só por `key` colapsaria as duas e o diff mentiria.
        def row_payloads(version)
          version.rows.pluck(:key, :data, :effective_from, :effective_until, :legal_basis)
                 .each_with_object({}) { |(key, data, from, till, basis), h| h[[key, from]] = { data:, effective_from: from, effective_until: till, legal_basis: basis } }
        end

        # Backfill (vigência anterior à de uma versão já publicada): quem fecha é a nova. Sem isto as duas ficavam
        # com effective_until nula e `version_effective_on` (ordem por version desc) fazia a retroativa valer
        # também no período da outra, que morria sem aviso.
        def closing_bound(others)
          nxt = others.where("effective_from > ?", @version.effective_from).minimum(:effective_from)
          return @version.effective_until if nxt.nil?
          [@version.effective_until, nxt - 1].compact.min
        end

        # Vigência anterior à nova: fecha na véspera e segue publicada (auditoria de período passado ainda a encontra).
        # Mesma data de início (caso comum do SyncJob): a anterior nunca chega a ter vigência exclusiva → retired.
        def close_previous!(prev)
          closing = @version.effective_from - 1
          return prev.update!(effective_until: [prev.effective_until, closing].compact.min) if closing >= prev.effective_from
          prev.update!(state: "retired", effective_until: [prev.effective_until, prev.effective_from].compact.min)
        end

        def set_table = @table = Catalog::ReferenceTable.find(params[:reference_table_id] || params[:id])
        def set_version = @version = @table.versions.find(params[:id])
        def serialize(v) = v.as_json(only: %i[id reference_table_id version effective_from effective_until state source_url notes published_at created_at]).merge(rows_count: v.rows.count)
      end
    end
  end
end
