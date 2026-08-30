module Api
  module V1
    module Admin
      class RuleTestCasesController < BaseController
        before_action :set_rule
        before_action :set_case, only: %i[update destroy run]

        def create
          tc = @rule.test_cases.create!(case_params)
          render json: tc, status: :created
        end

        def update
          @case.update!(case_params)
          render json: @case
        end

        def destroy
          @case.destroy!
          head :no_content
        end

        def run
          render json: result_json(Rules::TestRunner.new(@rule).run(@case))
        end

        def run_all
          render json: Rules::TestRunner.new(@rule).run_all.map { |r| result_json(r) }
        end

        private

        def set_rule = @rule = Rules::Rule.find(params[:rule_id])
        def set_case = @case = @rule.test_cases.find(params[:id])

        def case_params
          p = params.permit(:name, :reference_date)
          %w[scenario input catalog expect].each { |k| p[k] = params[k].to_unsafe_h if params[k].respond_to?(:to_unsafe_h) }
          p
        end

        def result_json(r) = { test_case_id: r.test_case.id, name: r.test_case.name, passed: r.passed, details: r.details, findings: r.findings, errors: r.errors }
      end
    end
  end
end
