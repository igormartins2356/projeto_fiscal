module Api
  module V1
    module Admin
      class BaseController < Api::V1::BaseController
        before_action :require_platform_admin!

        private

        # Callback nomeado: permite skip explícito (rota pública de leitura) sem introspecção de lambdas.
        def require_platform_admin! = require_role!("platform_admin")
      end
    end
  end
end
