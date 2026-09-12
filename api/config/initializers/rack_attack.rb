class Rack::Attack
  # Em produção o contador precisa ser compartilhado entre as réplicas: o cache padrão (file_store) daria a
  # cada container o seu próprio limite e zeraria a cada deploy. O bundle só tem redis-client (via Sidekiq),
  # para o qual o rack-attack não traz proxy — daí o adaptador mínimo abaixo.
  class RedisClientStore
    def initialize(url)
      @pool = RedisClient.config(url: url).new_pool(timeout: 1, size: 5)
    end

    def increment(key, amount = 1, expires_in: nil)
      @pool.pipelined do |redis|
        redis.call("INCRBY", key, amount)
        redis.call("EXPIRE", key, expires_in.to_i) if expires_in
      end.first
    end

    def read(key) = @pool.call("GET", key)

    def write(key, value, expires_in: nil)
      expires_in ? @pool.call("SET", key, value.to_s, "EX", expires_in.to_i) : @pool.call("SET", key, value.to_s)
    end

    def delete(key) = @pool.call("DEL", key)
  end

  # Cair no store padrão sem REDIS_URL daria a cada container o seu próprio contador (o oposto do que este
  # arquivo existe para garantir) e ninguém perceberia: em produção, faltar a variável quebra o boot.
  if Rails.env.production?
    raise "REDIS_URL não configurado: o contador do Rack::Attack ficaria por container e o limite de tentativas de login valeria por réplica" if ENV["REDIS_URL"].blank?
    Rack::Attack.cache.store = RedisClientStore.new(ENV["REDIS_URL"])
  else
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
  end

  # O front envia JSON (web/src/api/client.js), então `req.params` vinha vazio e as chaves por e-mail/usuário
  # ficavam nil: o throttle nunca contava. Lê o corpo uma única vez por requisição e rebobina para o Rails.
  def self.credentials(req)
    req.env["rack_attack.credentials"] ||=
      # Só lê o corpo se der para rebobinar: consumir a entrada sem devolver deixaria o Rails sem params.
      if req.media_type == "application/json" && req.body.respond_to?(:rewind)
        body = req.body.read.to_s
        req.body.rewind
        parsed = JSON.parse(body)
        parsed.is_a?(Hash) ? parsed : {}
      else
        req.params
      end
  rescue JSON::ParserError, EOFError, IOError
    req.env["rack_attack.credentials"] = {}
  end

  throttle("auth/login/ip", limit: 10, period: 60) { |req| req.ip if req.path == "/api/v1/auth/login" && req.post? }
  throttle("auth/login/email", limit: 5, period: 60) do |req|
    if req.path == "/api/v1/auth/login" && req.post?
      credentials(req)["email"].to_s.downcase.presence
    end
  end
  throttle("auth/mfa/ip", limit: 10, period: 60) { |req| req.ip if req.path.start_with?("/api/v1/auth/mfa") && req.post? }
  # Trocar de IP não pode dar tentativas extras contra o segundo fator do mesmo usuário.
  throttle("auth/mfa/user", limit: 5, period: 60) do |req|
    if req.path.start_with?("/api/v1/auth/mfa") && req.post?
      token = credentials(req)["mfa_token"].to_s
      begin
        ::Auth::Tokens.decode(token, purpose: "mfa")["sub"].to_s.presence if token.present?
      rescue ::Auth::Tokens::Invalid
        nil
      end
    end
  end
  throttle("api/ip", limit: 600, period: 60) { |req| req.ip if req.path.start_with?("/api/") }

  self.throttled_responder = ->(_req) { [429, { "Content-Type" => "application/json" }, [{ error: "muitas tentativas; aguarde um minuto" }.to_json]] }
end
Rack::Attack.enabled = !Rails.env.test?
Rails.application.config.middleware.use Rack::Attack
