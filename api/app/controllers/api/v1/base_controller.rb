module Api
  module V1
    # TODO(auth): JWT + current_user/current_firm. No MVP inicial usa header X-Client-Id apenas em dev.
    class BaseController < ApplicationController
      before_action :require_client

      private

      def current_client
        @current_client ||= Accounts::Client.find_by(id: request.headers["X-Client-Id"] || params[:client_id])
      end

      def require_client
        render json: { error: "client not found (X-Client-Id)" }, status: :unauthorized unless current_client
      end
    end
  end
end
