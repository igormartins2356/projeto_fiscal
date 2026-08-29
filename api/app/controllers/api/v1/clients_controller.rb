module Api
  module V1
    class ClientsController < ApplicationController
      def index = render(json: Accounts::Client.order(:legal_name).select(:id, :cnpj, :legal_name, :uf))
    end
  end
end
