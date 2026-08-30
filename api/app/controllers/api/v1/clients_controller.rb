module Api
  module V1
    class ClientsController < BaseController
      before_action :set_client, only: %i[show update]

      def index
        scope = firm_clients.order(:legal_name)
        scope = scope.where(active: true) unless params[:include_inactive] == "1"
        render json: scope.map { |c| serialize(c) }
      end

      def show = render(json: serialize(@client, detailed: true))

      def create
        client = firm_clients.new(client_params)
        client.save!
        audit!("client_created", subject: client)
        render json: serialize(client), status: :created
      end

      def update
        @client.update!(client_params)
        audit!("client_updated", subject: @client)
        render json: serialize(@client)
      end

      private

      def set_client = @client = firm_clients.find(params[:id])
      def client_params = params.permit(:cnpj, :legal_name, :trade_name, :uf, :city_code, :ie, :active).tap { |p| p[:cnpj] = p[:cnpj].to_s.gsub(/\D/, "") if p.key?(:cnpj) }

      def serialize(c, detailed: false)
        h = c.as_json(only: %i[id cnpj legal_name trade_name uf city_code ie active created_at])
        h[:current_scenario] = Scenario::TaxScenario.resolve(c, Date.current)&.slice(:id, :effective_from, :effective_until, :state) if detailed
        h[:documents_count] = c.documents.fiscal.count if detailed
        h
      end
    end
  end
end
