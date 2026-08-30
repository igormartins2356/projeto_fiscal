module Api
  module V1
    module Admin
      class RulesController < BaseController
        TRANSITIONS = { "draft" => %w[testing], "testing" => %w[draft shadow], "shadow" => %w[testing published], "published" => %w[retired], "retired" => [] }.freeze
        before_action :set_rule, only: %i[show update transition validate stats]

        def index
          scope = Rules::Rule.order(:code, version: :desc)
          scope = scope.where("code ILIKE ?", "%#{Rules::Rule.sanitize_sql_like(params[:q])}%") if params[:q].present?
          scope = scope.where(state: params[:state]) if params[:state].present?
          scope = scope.where(scope: params[:scope]) if params[:scope].present?
          scope = scope.where("? = ANY(tags)", params[:tag]) if params[:tag].present?
          scope = scope.where(source_type: params[:source_type]) if params[:source_type].present?
          rows, meta = paginate(scope)
          render json: meta.merge(data: rows.map { |r| serialize(r) })
        end

        def show
          render json: serialize(@rule, full: true)
        end

        # Cria regra nova (version 1) ou nova versão de um code existente (copia a última versão como base)
        def create
          code = params.require(:code)
          last = Rules::Rule.where(code:).order(version: :desc).first
          rule = Rules::Rule.new(code:, version: (last&.version || 0) + 1, state: "draft", created_by: current_user, source_type: "platform")
          rule.assign_attributes(last.slice(:title, :scope, :severity, :effective_from, :effective_until, :body, :tags, :dsl_version)) if last
          rule.assign_attributes(rule_params)
          rule.save!
          audit!("rule_created", subject: rule)
          render json: serialize(rule, full: true), status: :created
        end

        def update
          return render json: { error: "só rascunho/em teste podem ser editados; crie nova versão" }, status: :unprocessable_entity unless @rule.state.in?(%w[draft testing])
          @rule.update!(rule_params)
          render json: serialize(@rule, full: true)
        end

        def validate
          v = Rules::Validator.new(@rule.definition)
          v.valid?
          render json: { valid: v.errors.empty?, errors: v.errors, warnings: v.warnings }
        end

        # POST /admin/rules/:id/transition { to: "testing" }
        def transition
          to = params.require(:to)
          return render json: { error: "transição #{@rule.state} → #{to} não permitida" }, status: :unprocessable_entity unless TRANSITIONS[@rule.state].include?(to)
          if to == "testing"
            v = Rules::Validator.new(@rule.definition)
            return render json: { error: "regra inválida", errors: v.errors, warnings: v.warnings }, status: :unprocessable_entity unless v.valid?
          end
          if to == "shadow"
            results = Rules::TestRunner.new(@rule).run_all
            return render json: { error: "é preciso ao menos 1 caso que dispara e 1 que não dispara" }, status: :unprocessable_entity unless results.any? { |r| r.test_case.expect["findings"].present? } && results.any? { |r| r.test_case.expect["findings"].blank? }
            failed = results.reject(&:passed)
            return render json: { error: "#{failed.size} caso(s) de teste falhando", failures: failed.map { |f| { name: f.test_case.name, details: f.details } } }, status: :unprocessable_entity if failed.any?
          end
          @rule.update!(state: to, published_at: (to == "published" ? Time.current : @rule.published_at), effective_until: (to == "retired" && @rule.effective_until.nil? ? Date.current : @rule.effective_until))
          audit!("rule_transition", subject: @rule, to:)
          render json: serialize(@rule, full: true)
        end

        # Disparos recentes (modo sombra): findings por run nos últimos N runs
        def stats
          runs = Audit::AuditRun.where(state: "done").order(created_at: :desc).limit(params.fetch(:runs, 20).to_i)
          findings = Audit::Finding.where(rule_id: @rule.id, audit_run_id: runs.select(:id))
          render json: { runs: runs.size, findings: findings.count, by_state: findings.group(:state).count,
                         by_group: findings.group(:group_key).count.sort_by { |_, n| -n }.first(20).map { |g, n| { group_key: g, count: n } },
                         samples: findings.limit(10).map { |f| { message: f.message, evidence: f.evidence, document_id: f.document_id, item_number: f.item_number } } }
        end

        private

        def set_rule = @rule = Rules::Rule.find(params[:id])

        def rule_params
          p = params.permit(:title, :scope, :severity, :effective_from, :effective_until, :dsl_version, tags: [])
          p[:body] = params[:body].to_unsafe_h if params[:body].respond_to?(:to_unsafe_h)
          p
        end

        def serialize(r, full: false)
          h = r.as_json(only: %i[id code version title scope severity state source_type source_id effective_from effective_until tags dsl_version published_at created_at updated_at])
          if full
            h[:body] = r.body
            h[:test_cases] = r.test_cases.order(:id).map { |t| t.as_json(only: %i[id name reference_date scenario input catalog expect last_result last_run_at]) }
            h[:versions] = Rules::Rule.where(code: r.code).order(version: :desc).map { |v| v.slice(:id, :version, :state, :effective_from, :effective_until) }
            h[:allowed_transitions] = TRANSITIONS[r.state]
          end
          h
        end
      end
    end
  end
end
