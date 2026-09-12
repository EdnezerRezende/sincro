import { Body, Controller, Delete, Get, Param, Patch, Post, UseGuards } from '@nestjs/common';
import { FirebaseAuthGuard } from '../auth/firebase-auth.guard';
import { CurrentFirebaseUid } from '../common/current-firebase-uid.decorator';
import { UsersService } from '../users/users.service';
import { CartoesService } from './cartoes.service';
import { CreateCartaoDto } from './dto/create-cartao.dto';
import { UpdateCartaoDto } from './dto/update-cartao.dto';

@UseGuards(FirebaseAuthGuard)
@Controller('financas/cartoes')
export class CartoesController {
  constructor(
    private readonly cartoesService: CartoesService,
    private readonly usersService: UsersService,
  ) {}

  @Get()
  async list(@CurrentFirebaseUid() firebaseUid: string) {
    const user = await this.usersService.getByFirebaseUidOrThrow(firebaseUid);
    return this.cartoesService.list(user.id);
  }

  @Post()
  async create(@CurrentFirebaseUid() firebaseUid: string, @Body() dto: CreateCartaoDto) {
    const user = await this.usersService.getByFirebaseUidOrThrow(firebaseUid);
    return this.cartoesService.create(user.id, dto);
  }

  @Patch(':id')
  async update(
    @CurrentFirebaseUid() firebaseUid: string,
    @Param('id') id: string,
    @Body() dto: UpdateCartaoDto,
  ) {
    const user = await this.usersService.getByFirebaseUidOrThrow(firebaseUid);
    return this.cartoesService.update(user.id, id, dto);
  }

  @Delete(':id')
  async remove(@CurrentFirebaseUid() firebaseUid: string, @Param('id') id: string) {
    const user = await this.usersService.getByFirebaseUidOrThrow(firebaseUid);
    await this.cartoesService.remove(user.id, id);
    return { removed: true };
  }
}
