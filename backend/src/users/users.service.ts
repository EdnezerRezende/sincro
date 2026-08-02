import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';

@Injectable()
export class UsersService {
  constructor(private readonly prisma: PrismaService) {}

  async upsertByFirebaseUid(firebaseUid: string, nome: string) {
    return this.prisma.user.upsert({
      where: { firebaseUid },
      update: { nome },
      create: { firebaseUid, nome },
    });
  }

  async getByFirebaseUidOrThrow(firebaseUid: string) {
    const user = await this.prisma.user.findUnique({ where: { firebaseUid } });
    if (!user) {
      throw new NotFoundException('Usuário ainda não completou o cadastro inicial');
    }
    return user;
  }

  async getOnboardingStatus(firebaseUid: string) {
    const user = await this.getByFirebaseUidOrThrow(firebaseUid);
    const [sensoryProfile, trustedContactCount] = await Promise.all([
      this.prisma.sensoryProfile.findUnique({ where: { userId: user.id } }),
      this.prisma.trustedContact.count({ where: { userId: user.id } }),
    ]);

    return {
      userId: user.id,
      nome: user.nome,
      hasSensoryProfile: sensoryProfile !== null,
      trustedContactCount,
    };
  }

  async registerFcmToken(firebaseUid: string, fcmToken: string): Promise<void> {
    const user = await this.getByFirebaseUidOrThrow(firebaseUid);
    await this.prisma.user.update({ where: { id: user.id }, data: { fcmToken } });
  }
}
