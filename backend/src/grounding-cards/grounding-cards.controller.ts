import { Controller, Delete, Get, Param, Post, Query, UseGuards } from '@nestjs/common';
import { FirebaseAuthGuard } from '../auth/firebase-auth.guard';
import { CurrentFirebaseUid } from '../common/current-firebase-uid.decorator';
import { UsersService } from '../users/users.service';
import { GroundingCardsService } from './grounding-cards.service';

@UseGuards(FirebaseAuthGuard)
@Controller('grounding-cards')
export class GroundingCardsController {
  constructor(
    private readonly service: GroundingCardsService,
    private readonly usersService: UsersService,
  ) {}

  @Get()
  async list(@Query('categoria') categoria?: string) {
    return this.service.list(categoria);
  }

  @Get('favoritos')
  async listFavoritos(@CurrentFirebaseUid() firebaseUid: string) {
    const user = await this.usersService.getByFirebaseUidOrThrow(firebaseUid);
    return this.service.listFavoritos(user.id);
  }

  @Post(':id/favoritar')
  async favoritar(@CurrentFirebaseUid() firebaseUid: string, @Param('id') id: string) {
    const user = await this.usersService.getByFirebaseUidOrThrow(firebaseUid);
    await this.service.favoritar(user.id, id);
    return { success: true };
  }

  @Delete(':id/favoritar')
  async desfavoritar(@CurrentFirebaseUid() firebaseUid: string, @Param('id') id: string) {
    const user = await this.usersService.getByFirebaseUidOrThrow(firebaseUid);
    await this.service.desfavoritar(user.id, id);
    return { success: true };
  }
}
