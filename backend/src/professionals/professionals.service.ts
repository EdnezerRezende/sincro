import { Injectable } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { haversineDistanceKm } from '../common/geo';
import { CreateProfessionalDto } from './dto/create-professional.dto';
import { UpdateProfessionalDto } from './dto/update-professional.dto';

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

  async adminList() {
    return this.prisma.professional.findMany({ orderBy: { nome: 'asc' } });
  }

  async create(dto: CreateProfessionalDto) {
    return this.prisma.professional.create({ data: { ...dto, ativo: true } });
  }

  async update(id: string, dto: UpdateProfessionalDto) {
    return this.prisma.professional.update({ where: { id }, data: dto });
  }

  async deactivate(id: string): Promise<void> {
    await this.prisma.professional.update({ where: { id }, data: { ativo: false } });
  }
}
