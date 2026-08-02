import { Body, Controller, Delete, Get, Put, UseGuards } from '@nestjs/common';
import { FirebaseAuthGuard } from '../auth/firebase-auth.guard';
import { CurrentFirebaseUid } from '../common/current-firebase-uid.decorator';
import { SensoryProfileService } from './sensory-profile.service';
import { UpsertSensoryProfileDto } from './dto/upsert-sensory-profile.dto';

@UseGuards(FirebaseAuthGuard)
@Controller('sensory-profile')
export class SensoryProfileController {
  constructor(private readonly service: SensoryProfileService) {}

  @Put()
  async upsert(@CurrentFirebaseUid() firebaseUid: string, @Body() dto: UpsertSensoryProfileDto) {
    return this.service.upsert(firebaseUid, dto.dados);
  }

  @Get()
  async get(@CurrentFirebaseUid() firebaseUid: string) {
    return this.service.get(firebaseUid);
  }

  @Delete()
  async remove(@CurrentFirebaseUid() firebaseUid: string) {
    await this.service.remove(firebaseUid);
    return { success: true };
  }
}
