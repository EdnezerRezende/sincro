FROM node:22-alpine AS build
WORKDIR /app
# node:22-alpine's V8 heap-sizing heuristic can overshoot Docker Desktop's actual VM memory
# allocation, crashing `nest build` with "JavaScript heap out of memory" — cap it explicitly.
ENV NODE_OPTIONS=--max-old-space-size=2048
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
RUN npx prisma generate
RUN npm run build

FROM node:22-alpine AS runtime
WORKDIR /app
ENV NODE_ENV=production
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/dist ./dist
COPY --from=build /app/prisma ./prisma
COPY --from=build /app/prisma.config.ts ./prisma.config.ts
COPY --from=build /app/package.json ./package.json
EXPOSE 3000
# nest build's actual output is dist/src/main.js, not dist/main.js — tsconfig preserves the
# src/ prefix because prisma.config.ts sits outside src/, sharing the same compile root.
CMD ["sh", "-c", "npx prisma migrate deploy && node dist/src/main"]
