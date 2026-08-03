import { Body, Controller, Get, Patch, Post, UseGuards } from '@nestjs/common';
import { FirebaseAuthGuard } from '../auth/firebase-auth.guard';
import { CurrentFirebaseUid } from '../common/current-firebase-uid.decorator';
import { UsersService } from './users.service';
import { UpsertUserDto } from './dto/upsert-user.dto';
import { RegisterFcmTokenDto } from './dto/register-fcm-token.dto';
import { UpdateDiaRecebimentoDto } from './dto/update-dia-recebimento.dto';

@UseGuards(FirebaseAuthGuard)
@Controller('users')
export class UsersController {
  constructor(private readonly usersService: UsersService) {}

  @Post('me')
  async upsertMe(@CurrentFirebaseUid() firebaseUid: string, @Body() dto: UpsertUserDto) {
    return this.usersService.upsertByFirebaseUid(firebaseUid, dto.nome);
  }

  @Get('me')
  async getMe(@CurrentFirebaseUid() firebaseUid: string) {
    return this.usersService.getOnboardingStatus(firebaseUid);
  }

  @Post('me/fcm-token')
  async registerFcmToken(@CurrentFirebaseUid() firebaseUid: string, @Body() dto: RegisterFcmTokenDto) {
    await this.usersService.registerFcmToken(firebaseUid, dto.fcmToken);
    return { success: true };
  }

  @Patch('me/dia-recebimento')
  async updateDiaRecebimento(@CurrentFirebaseUid() firebaseUid: string, @Body() dto: UpdateDiaRecebimentoDto) {
    await this.usersService.updateDiaRecebimento(firebaseUid, dto.diaRecebimento);
    return { success: true };
  }
}
