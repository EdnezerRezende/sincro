import { Body, Controller, Delete, Get, Param, Post, UseGuards } from '@nestjs/common';
import { FirebaseAuthGuard } from '../auth/firebase-auth.guard';
import { CurrentFirebaseUid } from '../common/current-firebase-uid.decorator';
import { FinanceConnectionsService } from './finance-connections.service';
import { FinalizeConnectionDto } from './dto/finalize-connection.dto';

@UseGuards(FirebaseAuthGuard)
@Controller('financas')
export class FinanceController {
  constructor(private readonly connectionsService: FinanceConnectionsService) {}

  @Post('connect-token')
  async createConnectToken() {
    return this.connectionsService.createConnectToken();
  }

  @Post('conexoes')
  async finalize(@CurrentFirebaseUid() firebaseUid: string, @Body() dto: FinalizeConnectionDto) {
    return this.connectionsService.finalizeConnection(firebaseUid, dto.itemId);
  }

  @Get('conexoes')
  async list(@CurrentFirebaseUid() firebaseUid: string) {
    return this.connectionsService.listConnections(firebaseUid);
  }

  @Delete('conexoes/:id')
  async disconnect(@CurrentFirebaseUid() firebaseUid: string, @Param('id') id: string) {
    await this.connectionsService.disconnect(firebaseUid, id);
    return { success: true };
  }
}
