import { BadRequestException, Controller, Get, Query, UseGuards } from '@nestjs/common';
import { FirebaseAuthGuard } from '../auth/firebase-auth.guard';
import { ProfessionalsService } from './professionals.service';

@UseGuards(FirebaseAuthGuard)
@Controller('professionals')
export class ProfessionalsController {
  constructor(private readonly service: ProfessionalsService) {}

  @Get('search')
  async search(@Query('lat') latRaw: string, @Query('lng') lngRaw: string, @Query('tags') tagsRaw?: string) {
    if (!latRaw?.trim() || !lngRaw?.trim()) {
      throw new BadRequestException('lat e lng são obrigatórios e devem ser números');
    }
    const lat = Number(latRaw);
    const lng = Number(lngRaw);
    if (Number.isNaN(lat) || Number.isNaN(lng)) {
      throw new BadRequestException('lat e lng são obrigatórios e devem ser números');
    }
    const tags = tagsRaw
      ? tagsRaw
          .split(',')
          .map((tag) => tag.trim())
          .filter((tag) => tag.length > 0)
      : undefined;
    return this.service.search(lat, lng, tags);
  }

  @Get('tags')
  async tags() {
    return this.service.listActiveTags();
  }
}
