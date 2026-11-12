# Pastefy for Railway.
#
# Pastefy (interaapps/pastefy, MIT) is a Java pastebin with a REST API v2 over MySQL/MariaDB. A stock deploy has three
# defects for an agent that has to drive it. Anyone can create pastes without signing in (the default), the only way
# to authenticate an API client is an API key that belongs to a user, and a user can only be created by signing in
# through an OAuth provider, so a fresh instance has no way to produce a credential without a human and an identity
# provider. The server also ignores PORT (it listens on HTTP_SERVER_PORT, default 80).
#
# This wrapper (1) registers the OIDC provider with unreachable endpoints. Pastefy only honours API keys when at
# least one auth provider is registered, and nobody can complete a sign-in against an endpoint that answers nothing.
# (2) turns on PASTEFY_LOGIN_REQUIRED_CREATE so an anonymous or wrong-key write is answered 401. (3) at every boot,
# once the app has created its tables, inserts an ADMIN user and the API key from PASTEFY_API_KEY. (4) listens on $PORT.
# The application is otherwise untouched.
FROM interaapps/pastefy:7.2.6@sha256:d2abe24232aa54023c472b033fe50cc8db0df8769bbe8099575d2bdaeed3ecb0

USER root
RUN apt-get update \
 && apt-get install -y --no-install-recommends mariadb-client \
 && rm -rf /var/lib/apt/lists/* \
 && command -v mariadb

ENV DATABASE_DRIVER=mysql \
    DATABASE_PORT=3306 \
    OAUTH2_OIDC_CLIENT_ID=railway-unused \
    OAUTH2_OIDC_CLIENT_SECRET=railway-unused \
    OAUTH2_OIDC_AUTH_ENDPOINT=http://127.0.0.1:9/oidc/auth \
    OAUTH2_OIDC_TOKEN_ENDPOINT=http://127.0.0.1:9/oidc/token \
    OAUTH2_OIDC_USERINFO_ENDPOINT=http://127.0.0.1:9/oidc/userinfo \
    PASTEFY_LOGIN_REQUIRED_CREATE=true

COPY --chmod=0755 railway-entrypoint.sh /usr/local/bin/railway-entrypoint.sh

EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/railway-entrypoint.sh"]
