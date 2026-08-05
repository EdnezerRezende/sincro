import { Injectable } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { haversineDistanceKm } from '../common/geo';

@Injectable()
export class ProfessionalsService {
  constructor(private readonly prisma: PrismaService) {}

  async search(lat: number, lng: number, tags?: string[]) {
    const professionals = await this.prisma.professional.findMany({
      where: tags && tags.length > 0 ? { ativo: true, tags: { hasSome: tags } } : { ativo: true },
    });

    return professionals
      .map((professional) => ({
        ...professional,
        distanciaKm: haversineDistanceKm(lat, lng, professional.latitude, professional.longitude),
      }))
      .sort((a, b) => a.distanciaKm - b.distanciaKm);
  }

  async listActiveTags(): Promise<string[]> {
    const professionals = await this.prisma.professional.findMany({
      where: { ativo: true },
      select: { tags: true },
    });
    const tagSet = new Set<string>();
    professionals.forEach((professional) => professional.tags.forEach((tag) => tagSet.add(tag)));
    return Array.from(tagSet).sort();
  }
}
