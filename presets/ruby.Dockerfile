# syntax=docker/dockerfile:1
# updatool preset — Ruby / Rails
FROM ruby:3.3-slim
WORKDIR /app
ENV BUNDLE_WITHOUT=development:test RAILS_ENV=production PORT=3000
RUN apt-get update -qq && apt-get install -y --no-install-recommends build-essential libpq-dev && rm -rf /var/lib/apt/lists/*
COPY Gemfile Gemfile.lock ./
RUN --mount=type=cache,target=/usr/local/bundle/cache bundle install
COPY . .
RUN --mount=type=cache,target=/app/tmp/cache SECRET_KEY_BASE_DUMMY=1 bundle exec rails assets:precompile
EXPOSE 3000
CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0"]
