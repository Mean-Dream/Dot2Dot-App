# Stage 1: Build
FROM node:20-slim AS base

# Install pnpm
ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"
RUN corepack enable pnpm

WORKDIR /app

# Copy configuration files
COPY package.json pnpm-lock.yaml* tsconfig.json ./

# Install dependencies
RUN pnpm install

# Copy source code
COPY . .

# Build TypeScript to JavaScript
RUN pnpm build

# Stage 2: Runtime
FROM node:20-slim
WORKDIR /app

# Copy only necessary files from build stage
COPY --from=base /app/node_modules ./node_modules
COPY --from=base /app/dist ./dist
COPY --from=base /app/package.json ./package.json

EXPOSE 8080

# Run the compiled JS from the dist folder
CMD [ "node", "dist/index.js" ]