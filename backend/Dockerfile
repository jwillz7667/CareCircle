FROM node:22-bookworm-slim AS base
ENV PNPM_HOME=/pnpm
ENV PATH=$PNPM_HOME:$PATH
RUN corepack enable && corepack prepare pnpm@9.12.3 --activate

WORKDIR /app

COPY backend/pnpm-lock.yaml backend/pnpm-workspace.yaml backend/package.json ./
COPY backend/packages/db/package.json packages/db/
COPY backend/packages/shared/package.json packages/shared/
COPY backend/apps/api/package.json apps/api/
COPY backend/apps/worker/package.json apps/worker/
COPY backend/apps/migrator/package.json apps/migrator/
RUN pnpm install --frozen-lockfile

COPY backend/ ./

CMD ["pnpm", "--filter", "@carecircle/api", "start"]
