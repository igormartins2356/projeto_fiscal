module Api
  module V1
    # Gestão de usuários da firma (firm_admin). platform_admin pode informar firm_id.
    class UsersController < BaseController
      # change_password é do próprio usuário: qualquer papel troca a própria senha.
      before_action -> { require_role!("firm_admin") }, except: :change_password
      before_action :set_user, only: %i[update destroy]
      before_action :protect_platform_admin!, only: %i[update destroy]
      before_action :reject_platform_admin_role!, only: %i[create update]

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
        new_password = user_params[:password].presence
        @user.update!(user_params.except(:password).merge(new_password ? { password: new_password, password_changed_at: Time.current } : {}))
        # Senha trocada pelo admin derruba as sessões abertas: os refresh tokens são revogados e `password_changed_at`
        # invalida os access tokens já emitidos (Auth::Tokens#issue_access / ApplicationController#current_user).
        @user.refresh_tokens.update_all(revoked_at: Time.current) if new_password
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
        # A troca invalida todo token emitido antes dela, inclusive o de quem está trocando: devolvemos
        # uma sessão nova para não expulsar da tela quem acabou de trocar a própria senha.
        render json: { access_token: ::Auth::Tokens.issue_access(current_user),
                       refresh_token: ::Auth::Tokens.issue_refresh(current_user, request:),
                       expires_in: ::Auth::Tokens::ACCESS_TTL.to_i }
      end

      private

      def scope = current_user.platform_admin? ? Accounts::User.all : Accounts::User.where(firm_id: current_firm.id)
      def set_user = @user = scope.find(params[:id])

      # Sem isto, um firm_admin da mesma firma troca senha/e-mail do platform_admin e assume acesso global.
      def protect_platform_admin!
        return unless @user.platform_admin? && !current_user.platform_admin?
        render json: { error: "somente o administrador da plataforma pode alterar ou desativar um administrador da plataforma" }, status: :forbidden
      end

      # Rebaixar o papel em silêncio escondia a tentativa de escalar privilégio; recusa explícita.
      def reject_platform_admin_role!
        return unless params[:role].to_s == "platform_admin" && !current_user.platform_admin?
        render json: { error: "papel não permitido" }, status: :unprocessable_entity
      end

      def target_firm_id = current_user.platform_admin? && params[:firm_id].present? ? params[:firm_id] : current_firm.id

      def user_params
        params.permit(:name, :email, :password, :role, :active)
      end

      def serialize(u) = u.as_json(only: %i[id name email role active otp_enabled last_sign_in_at created_at firm_id])
    end
  end
end
