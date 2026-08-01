import { Injectable, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { PrismaPg } from '@prisma/adapter-pg';
import { PrismaClient } from '@prisma/client';

// Prisma 7's `prisma-client-js` generator requires a driver adapter to be
// passed explicitly to the PrismaClient constructor (the schema's
// `datasource` block can no longer carry a `url`). We build the adapter
// from DATABASE_URL here so the rest of the app can keep using
// `new PrismaClient()`-style semantics via this service.
const adapter = new PrismaPg({ connectionString: process.env.DATABASE_URL });

@Injectable()
export class PrismaService extends PrismaClient implements OnModuleInit, OnModuleDestroy {
  constructor() {
    super({ adapter });
  }

  async onModuleInit() {
    await this.$connect();
  }

  async onModuleDestroy() {
    await this.$disconnect();
  }
}
