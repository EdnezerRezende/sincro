import { Body, Controller, Get, Post, UseGuards } from '@nestjs/common';
import { FirebaseAuthGuard } from '../auth/firebase-auth.guard';
import { CurrentFirebaseUid } from '../common/current-firebase-uid.decorator';
import { UsersService } from './users.service';
import { UpsertUserDto } from './dto/upsert-user.dto';

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
}
