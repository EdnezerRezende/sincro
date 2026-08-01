import { Body, Controller, Delete, Get, Param, Post, UseGuards } from '@nestjs/common';
import { FirebaseAuthGuard } from '../auth/firebase-auth.guard';
import { CurrentFirebaseUid } from '../common/current-firebase-uid.decorator';
import { TrustedContactsService } from './trusted-contacts.service';
import { CreateTrustedContactDto } from './dto/create-trusted-contact.dto';

@UseGuards(FirebaseAuthGuard)
@Controller('trusted-contacts')
export class TrustedContactsController {
  constructor(private readonly service: TrustedContactsService) {}

  @Post()
  async create(@CurrentFirebaseUid() firebaseUid: string, @Body() dto: CreateTrustedContactDto) {
    return this.service.create(firebaseUid, dto);
  }

  @Get()
  async list(@CurrentFirebaseUid() firebaseUid: string) {
    return this.service.list(firebaseUid);
  }

  @Delete(':id')
  async remove(@CurrentFirebaseUid() firebaseUid: string, @Param('id') id: string) {
    await this.service.remove(firebaseUid, id);
    return { success: true };
  }
}
