import { Body, Controller, Delete, Get, Param, Patch, Post, UseGuards } from '@nestjs/common';
import { FirebaseAuthGuard } from '../auth/firebase-auth.guard';
import { AdminGuard } from '../common/admin.guard';
import { GroundingCardsService } from './grounding-cards.service';
import { CreateGroundingCardDto } from './dto/create-grounding-card.dto';
import { UpdateGroundingCardDto } from './dto/update-grounding-card.dto';

@UseGuards(FirebaseAuthGuard, AdminGuard)
@Controller('admin/grounding-cards')
export class AdminGroundingCardsController {
  constructor(private readonly service: GroundingCardsService) {}

  @Get()
  async list() {
    return this.service.adminList();
  }

  @Post()
  async create(@Body() dto: CreateGroundingCardDto) {
    return this.service.create(dto);
  }

  @Patch(':id')
  async update(@Param('id') id: string, @Body() dto: UpdateGroundingCardDto) {
    return this.service.update(id, dto);
  }

  @Delete(':id')
  async deactivate(@Param('id') id: string) {
    await this.service.deactivate(id);
    return { success: true };
  }
}
