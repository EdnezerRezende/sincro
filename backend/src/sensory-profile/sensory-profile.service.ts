import { Injectable } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { UsersService } from '../users/users.service';

@Injectable()
export class SensoryProfileService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly usersService: UsersService,
  ) {}

  async upsert(firebaseUid: string, dados: Record<string, unknown>) {
    const user = await this.usersService.getByFirebaseUidOrThrow(firebaseUid);
    return this.prisma.sensoryProfile.upsert({
      where: { userId: user.id },
      update: { dados },
      create: { userId: user.id, dados },
    });
  }

  async get(firebaseUid: string) {
    const user = await this.usersService.getByFirebaseUidOrThrow(firebaseUid);
    return this.prisma.sensoryProfile.findUnique({ where: { userId: user.id } });
  }
}
