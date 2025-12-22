ARG NODE_VERSION=22.21.1
ARG N8N_VERSION=2.1.1

FROM node:${NODE_VERSION}-alpine AS base

# Install build dependencies and runtime tools
RUN apk add --no-cache \
    sqlite \
    curl \
    jq \
    python3 \
    make \
    g++ \
    linux-headers \
    libgcc \
    libstdc++ \
    libffi-dev \
    openssl-dev \
    pixman-dev \
    cairo-dev \
    pango-dev \
    jpeg-dev \
    giflib-dev \
    tiff-dev \
    ghostscript-dev

WORKDIR /app

# Install n8n globally
RUN npm install -g n8n@${N8N_VERSION}

# Create node user and set permissions
RUN adduser -S node -u 1001 || true && \
    mkdir -p /home/node/.n8n && \
    chown -R node:node /home/node

# Install canvas dependencies as root
USER root
RUN cd /usr/local/lib/node_modules/n8n/node_modules/pdfjs-dist && \
    npm install @napi-rs/canvas

USER node

EXPOSE 5678

ENTRYPOINT ["n8n", "start"]

