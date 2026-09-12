module Api
  module V1
    # Tudo aqui exige usuário autenticado. Recursos por cliente usam `current_client`, sempre dentro da firma do usuário.
    class BaseController < ApplicationController
      before_action :authenticate!

      private

      def firm_clients = Accounts::Client.where(firm_id: current_firm.id)

      def current_client
        @current_client ||= firm_clients.find_by(id: request.headers["X-Client-Id"] || params[:client_id])
      end

      def require_client!
        render json: { error: "cliente não informado ou não pertence à sua firma (X-Client-Id)" }, status: :unprocessable_entity unless current_client
      end

      # Listagens paginadas: { data, total, page, per_page }
      def paginate(scope)
        per_page = params.fetch(:per_page, 25).to_i.clamp(1, 200)
        page = [params.fetch(:page, 1).to_i, 1].max
        total = scope.count
        [scope.offset((page - 1) * per_page).limit(per_page), { total:, page:, per_page: }]
      end
    end
  end
end
