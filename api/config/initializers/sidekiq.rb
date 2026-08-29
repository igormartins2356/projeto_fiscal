redis = { url: ENV.fetch("REDIS_URL", "redis://redis:6379/0") }
Sidekiq.configure_server { |c| c.redis = redis }
Sidekiq.configure_client { |c| c.redis = redis }
