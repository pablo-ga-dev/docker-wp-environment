FROM wordpress:php8.3-apache

ENV NODE_VERSION=22.19.0 \
    COMPOSER_VERSION=2.8.1 \
    WPCLI_VERSION=2.12.0

RUN apt-get update && apt-get install -y --no-install-recommends \
      git curl unzip zip less vim nano \
      default-mysql-client \
    && rm -rf /var/lib/apt/lists/*

# ---- Node.js + npm (binarios oficiales) ----
RUN ARCH="$(dpkg --print-architecture)"; \
    case "$ARCH" in \
      amd64)  NODE_ARCH="x64" ;; \
      arm64)  NODE_ARCH="arm64" ;; \
      armhf)  NODE_ARCH="armv7l" ;; \
      *) echo "Arquitectura no soportada: $ARCH" && exit 1 ;; \
    esac; \
    curl -fsSL "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-${NODE_ARCH}.tar.xz" -o /tmp/node.tar.xz \
 && tar -xJf /tmp/node.tar.xz -C /usr/local --strip-components=1 \
 && rm /tmp/node.tar.xz \
 && node -v && npm -v

# pnpm y yarn global
RUN npm install -g pnpm yarn

# ---- Composer ----
RUN curl -fsSL -o /usr/local/bin/composer \
      "https://getcomposer.org/download/${COMPOSER_VERSION}/composer.phar" \
 && chmod +x /usr/local/bin/composer \
 && composer --version

# ---- WP-CLI ----
RUN curl -fsSL -o /usr/local/bin/wp \
      "https://github.com/wp-cli/wp-cli/releases/download/v${WPCLI_VERSION}/wp-cli-${WPCLI_VERSION}.phar" \
 && chmod +x /usr/local/bin/wp \
 && wp --allow-root --version

# Habilitar shell y HOME para www-data (para terminales VS Code)
RUN usermod -d /var/www -s /bin/bash www-data \
    && mkdir -p /var/www/html \
    && chown -R www-data:www-data /var/www

USER www-data
