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
    end
  end
end
