import { Controller, Post, UseGuards } from '@nestjs/common';
import { FirebaseAuthGuard } from '../auth/firebase-auth.guard';
import { CurrentFirebaseUid } from '../common/current-firebase-uid.decorator';
import { FinanceSyncService } from './finance-sync.service';

@UseGuards(FirebaseAuthGuard)
@Controller('financas')
export class FinanceSyncController {
  constructor(private readonly financeSyncService: FinanceSyncService) {}

  @Post('sync')
  async sync(@CurrentFirebaseUid() firebaseUid: string) {
    await this.financeSyncService.syncAllForUser(firebaseUid);
    return { success: true };
  }
}
