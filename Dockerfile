ARG NODE_VERSION=22.21.1
ARG N8N_VERSION=2.1.1

FROM node:${NODE_VERSION}-alpine AS base

ARG N8N_VERSION

RUN apk add --no-cache \
    postgresql-client \
    curl \
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

RUN apk add --no-cache \
    git \
    jq \
    rsync \
    sqlite

WORKDIR /app

RUN npm install -g n8n@${N8N_VERSION}

COPY --chown=node:node scripts /app/scripts
COPY --chown=node:node workflows /app/workflows
COPY --chown=node:node databases /app/databases
COPY --chown=node:node tests /app/tests
COPY --chown=node:node credentials /tmp/credentials

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

USER node

EXPOSE 5678

ENTRYPOINT ["/entrypoint.sh"]
CMD ["n8n", "start"]
