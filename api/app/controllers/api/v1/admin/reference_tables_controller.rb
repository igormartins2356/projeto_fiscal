module Api
  module V1
    module Admin
      class ReferenceTablesController < BaseController
        # GET /api/v1/reference_tables (fora do namespace admin) lista o identificador e a chave das tabelas
        # para qualquer usuário autenticado; os campos internos (fonte, schema, revisão) ficam só no admin.
        skip_before_action :require_platform_admin!, only: :index
        before_action :require_platform_admin_outside_public_route!, only: :index
        before_action :set_table, only: %i[show update]

        def index
          render json: Catalog::ReferenceTable.order(:code).map { |t| public_listing? ? public_serialize(t) : serialize(t) }
        end

        def show = render(json: serialize(@table, full: true))

        # GET /admin/reference_tables/curation_queue — lacunas agregadas dos últimos runs (fila de curadoria por demanda)
        def curation_queue
          runs = Audit::AuditRun.where(state: "done").where("created_at > ?", 90.days.ago).order(created_at: :desc).limit(200)
          agg = Hash.new { |h, k| h[k] = { items: 0, clients: Set.new } }
          runs.each do |run|
            %w[st_uf icms_internal_rate_ncm].each do |kind|
              Array(run.coverage[kind]).each do |e|
                key = [kind, e["uf"], e["ncm"]]
                agg[key][:items] += e["items"].to_i
                agg[key][:clients] << run.client_id
              end
            end
          end
          rows = agg.map { |(kind, uf, ncm), v| { table: kind == "st_uf" ? "st_uf" : "icms_internal_rate", uf:, ncm:, items: v[:items], clients: v[:clients].size } }
                    .sort_by { |r| -r[:items] }.first(100)
          render json: { generated_at: Time.current, runs_considered: runs.size, rows: }
        end

        def create
          t = Catalog::ReferenceTable.create!(table_params)
          audit!("reference_table_created", subject: t, code: t.code)
          render json: serialize(t, full: true), status: :created
        end

        def update
          @table.update!(table_params)
          audit!("reference_table_updated", subject: @table, code: @table.code)
          render json: serialize(@table, full: true)
        end

        private

        # Só a rota pública (/api/v1/reference_tables) dispensa platform_admin. O marcador é lido de
        # `path_parameters` (defaults da rota), que a query string não consegue forjar.
        def public_listing? = request.path_parameters[:public_listing].present?

        def require_platform_admin_outside_public_route!
          require_platform_admin! unless public_listing?
        end

        def set_table = @table = Catalog::ReferenceTable.find(params[:id])
        def table_params
          p = params.permit(:code, :name, :source_class, :source_url, :next_review_on, key_names: [])
          p[:key_arity] = p[:key_names].size if p[:key_names]
          p[:row_schema] = params[:row_schema].to_unsafe_h if params[:row_schema].respond_to?(:to_unsafe_h)
          p
        end

        # Listagem pública: só o que a tela do contador usa para escolher a tabela de uma sobreposição.
        def public_serialize(t)
          t.as_json(only: %i[id code name key_arity key_names])
           .merge(current_version: t.version_effective_on(Date.current)&.slice(:id, :version, :effective_from, :effective_until))
        end

        def serialize(t, full: false)
          h = t.as_json(only: %i[id code name key_arity key_names row_schema source_class source_url next_review_on created_at])
          h[:current_version] = t.version_effective_on(Date.current)&.slice(:id, :version, :effective_from, :effective_until)
          h[:versions] = t.versions.order(version: :desc).map { |v| v.as_json(only: %i[id version effective_from effective_until state source_url notes published_at created_at]).merge(rows_count: v.rows.count) } if full
          h
        end
      end
    end
  end
end
