module Api
  module V1
    # Gestão de usuários da firma (firm_admin). platform_admin pode informar firm_id.
    class UsersController < BaseController
      before_action -> { require_role!("firm_admin") }
      before_action :set_user, only: %i[update destroy]

      def index
        render json: scope.order(:name).map { |u| serialize(u) }
      end

      def create
        user = scope.new(user_params.merge(firm_id: target_firm_id))
        user.save!
        audit!("user_created", subject: user)
        render json: serialize(user), status: :created
      end

      def update
        @user.update!(user_params.except(:password).merge(user_params[:password].present? ? { password: user_params[:password] } : {}))
        audit!("user_updated", subject: @user)
        render json: serialize(@user)
      end

      def destroy
        return render json: { error: "não é possível remover a si mesmo" }, status: :unprocessable_entity if @user == current_user
        @user.update!(active: false)
        @user.refresh_tokens.update_all(revoked_at: Time.current)
        audit!("user_deactivated", subject: @user)
        head :no_content
      end

      def change_password
        return render json: { error: "senha atual inválida" }, status: :unprocessable_entity unless current_user.authenticate(params.require(:current_password))
        current_user.update!(password: params.require(:password), password_changed_at: Time.current)
        current_user.refresh_tokens.update_all(revoked_at: Time.current)
        audit!("password_changed")
        head :no_content
      end

      private

      def scope = current_user.platform_admin? ? Accounts::User.all : Accounts::User.where(firm_id: current_firm.id)
      def set_user = @user = scope.find(params[:id])
      def target_firm_id = current_user.platform_admin? && params[:firm_id].present? ? params[:firm_id] : current_firm.id

      def user_params
        p = params.permit(:name, :email, :password, :role, :active)
        p[:role] = "accountant" if p[:role] == "platform_admin" && !current_user.platform_admin?
        p
      end

      def serialize(u) = u.as_json(only: %i[id name email role active otp_enabled last_sign_in_at created_at firm_id])
    end
  end
end
