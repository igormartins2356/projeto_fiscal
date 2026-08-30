module Api
  module V1
    # Cenários tributários de um cliente: versões com vigência. Só rascunho é editável; publicar fecha a versão anterior.
    class TaxScenariosController < BaseController
      before_action :set_client
      before_action :set_scenario, only: %i[show update publish destroy]

      def index = render(json: @client.tax_scenarios.order(effective_from: :desc, id: :desc).map { |s| serialize(s) })
      def show = render(json: serialize(@scenario))

      def create
        scenario = @client.tax_scenarios.new(scenario_params.merge(state: "draft", created_by: current_user))
        scenario.save!
        audit!("scenario_created", subject: scenario)
        render json: serialize(scenario), status: :created
      end

      def update
        return render json: { error: "cenário publicado não pode ser editado; crie uma nova versão" }, status: :unprocessable_entity unless @scenario.state == "draft"
        @scenario.update!(scenario_params)
        render json: serialize(@scenario)
      end

      def publish
        return render json: { error: "já publicado" }, status: :unprocessable_entity if @scenario.state == "published"
        errors = Scenario::Validator.new(@scenario.data).errors
        return render json: { error: "cenário inválido", errors: }, status: :unprocessable_entity if errors.any?
        Scenario::TaxScenario.transaction do
          @client.tax_scenarios.published.where("effective_from < ?", @scenario.effective_from).where(effective_until: nil)
                 .update_all(effective_until: @scenario.effective_from - 1)
          @scenario.update!(state: "published")
        end
        audit!("scenario_published", subject: @scenario)
        render json: serialize(@scenario)
      end

      def destroy
        return render json: { error: "só rascunhos podem ser excluídos" }, status: :unprocessable_entity unless @scenario.state == "draft"
        @scenario.destroy!
        head :no_content
      end

      # POST /clients/:client_id/tax_scenarios/infer → proposta a partir das notas (não persiste)
      def infer
        render json: Scenario::Inference.new(@client, months: params.fetch(:months, 6).to_i).call
      end

      private

      def set_client = @client = firm_clients.find(params[:client_id])
      def set_scenario = @scenario = @client.tax_scenarios.find(params[:id])

      def scenario_params
        p = params.permit(:effective_from, :effective_until, data: {}, field_origins: {})
        p[:data] = params[:data].to_unsafe_h if params[:data].respond_to?(:to_unsafe_h)
        p[:field_origins] = params[:field_origins].to_unsafe_h if params[:field_origins].respond_to?(:to_unsafe_h)
        p
      end

      def serialize(s) = s.as_json(only: %i[id client_id effective_from effective_until state data field_origins created_by_id created_at updated_at])
    end
  end
end
