import { Injectable, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { PrismaPg } from '@prisma/adapter-pg';
import { PrismaClient } from '@prisma/client';

@Injectable()
export class PrismaService extends PrismaClient implements OnModuleInit, OnModuleDestroy {
  constructor() {
    // Prisma 7's `prisma-client-js` generator requires a driver adapter to
    // be passed explicitly to the PrismaClient constructor (the schema's
    // `datasource` block can no longer carry a `url`). The adapter is built
    // here, inside the constructor, rather than as a module-level constant,
    // so that (a) pool construction only happens when Nest's DI container
    // actually instantiates this service — not as an import side effect —
    // and (b) `process..env.DATABASE_URL` is read lazily, after
    // `main.ts`'s `import 'dotenv/config'` has already populated it.
    const adapter = new PrismaPg({ connectionString: process.env.DATABASE_URL });
    super({ adapter });
  }

  async onModuleInit() {
    await this.$connect();
  }

  async onModuleDestroy() {
    await this.$disconnect();
  }
}
