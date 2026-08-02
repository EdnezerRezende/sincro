import { Controller, Get, UseGuards } from '@nestjs/common';
import { FirebaseAuthGuard } from '../auth/firebase-auth.guard';
import { CurrentFirebaseUid } from '../common/current-firebase-uid.decorator';
import { EmailSyncService } from './email-sync.service';

@UseGuards(FirebaseAuthGuard)
@Controller('resumos-email')
export class EmailSummaryController {
  constructor(private readonly emailSyncService: EmailSyncService) {}

  @Get()
  async list(@CurrentFirebaseUid() firebaseUid: string) {
    return this.emailSyncService.list(firebaseUid);
  }
}
