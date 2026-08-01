import { Body, Controller, Post, UseGuards } from '@nestjs/common';
import { FirebaseAuthGuard } from '../auth/firebase-auth.guard';
import { CurrentFirebaseUid } from '../common/current-firebase-uid.decorator';
import { EmergencyService } from './emergency.service';
import { BuildEmergencyMessageDto } from './dto/build-emergency-message.dto';

@UseGuards(FirebaseAuthGuard)
@Controller('emergency')
export class EmergencyController {
  constructor(private readonly service: EmergencyService) {}

  @Post('message')
  async buildMessage(@CurrentFirebaseUid() firebaseUid: string, @Body() dto: BuildEmergencyMessageDto) {
    return this.service.buildMessage(firebaseUid, dto.contactId);
  }
}
