import { Body, Controller, Delete, Get, Post, UseGuards } from '@nestjs/common';
import { FirebaseAuthGuard } from '../auth/firebase-auth.guard';
import { CurrentFirebaseUid } from '../common/current-firebase-uid.decorator';
import { GmailConnectionsService } from './gmail-connections.service';
import { ConnectGmailDto } from './dto/connect-gmail.dto';

@UseGuards(FirebaseAuthGuard)
@Controller('gmail')
export class GmailController {
  constructor(private readonly connectionsService: GmailConnectionsService) {}

  @Post('connect')
  async connect(@CurrentFirebaseUid() firebaseUid: string, @Body() dto: ConnectGmailDto) {
    await this.connectionsService.connect(firebaseUid, dto.serverAuthCode);
    return { success: true };
  }

  @Get('connection')
  async status(@CurrentFirebaseUid() firebaseUid: string) {
    return this.connectionsService.status(firebaseUid);
  }

  @Delete('connection')
  async disconnect(@CurrentFirebaseUid() firebaseUid: string) {
    await this.connectionsService.disconnect(firebaseUid);
    return { success: true };
  }
}
