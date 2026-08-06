import { Body, Controller, Delete, Get, Param, Patch, Post, UseGuards } from '@nestjs/common';
import { FirebaseAuthGuard } from '../auth/firebase-auth.guard';
import { AdminGuard } from '../common/admin.guard';
import { ProfessionalsService } from './professionals.service';
import { CreateProfessionalDto } from './dto/create-professional.dto';
import { UpdateProfessionalDto } from './dto/update-professional.dto';

@UseGuards(FirebaseAuthGuard, AdminGuard)
@Controller('admin/professionals')
export class AdminProfessionalsController {
  constructor(private readonly service: ProfessionalsService) {}

  @Get()
  async list() {
    return this.service.adminList();
  }

  @Post()
  async create(@Body() dto: CreateProfessionalDto) {
    return this.service.create(dto);
  }

  @Patch(':id')
  async update(@Param('id') id: string, @Body() dto: UpdateProfessionalDto) {
    return this.service.update(id, dto);
  }

  @Delete(':id')
  async deactivate(@Param('id') id: string) {
    await this.service.deactivate(id);
    return { success: true };
  }
}
