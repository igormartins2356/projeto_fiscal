module Api
  module V1
    module Admin
      class BaseController < Api::V1::BaseController
        before_action -> { require_role!("platform_admin") }

        private

        def paginate(scope)
          per_page = params.fetch(:per_page, 25).to_i.clamp(1, 200)
          page = [params.fetch(:page, 1).to_i, 1].max
          total = scope.count
          [scope.offset((page - 1) * per_page).limit(per_page), { total:, page:, per_page: }]
        end
      end
    end
  end
end
