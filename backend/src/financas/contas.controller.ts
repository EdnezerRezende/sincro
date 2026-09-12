import { Body, Controller, Delete, Get, Param, Patch, Post, UseGuards } from '@nestjs/common';
import { FirebaseAuthGuard } from '../auth/firebase-auth.guard';
import { CurrentFirebaseUid } from '../common/current-firebase-uid.decorator';
import { UsersService } from '../users/users.service';
import { ContasService } from './contas.service';
import { CreateContaDto } from './dto/create-conta.dto';
import { UpdateContaDto } from './dto/update-conta.dto';

@UseGuards(FirebaseAuthGuard)
@Controller('financas/contas')
export class ContasController {
  constructor(
    private readonly contasService: ContasService,
    private readonly usersService: UsersService,
  ) {}

  @Get()
  async list(@CurrentFirebaseUid() firebaseUid: string) {
    const user = await this.usersService.getByFirebaseUidOrThrow(firebaseUid);
    return this.contasService.list(user.id);
  }

  @Post()
  async create(@CurrentFirebaseUid() firebaseUid: string, @Body() dto: CreateContaDto) {
    const user = await this.usersService.getByFirebaseUidOrThrow(firebaseUid);
    return this.contasService.create(user.id, dto);
  }

  @Patch(':id')
  async update(
    @CurrentFirebaseUid() firebaseUid: string,
    @Param('id') id: string,
    @Body() dto: UpdateContaDto,
  ) {
    const user = await this.usersService.getByFirebaseUidOrThrow(firebaseUid);
    return this.contasService.update(user.id, id, dto);
  }

  @Delete(':id')
  async remove(@CurrentFirebaseUid() firebaseUid: string, @Param('id') id: string) {
    const user = await this.usersService.getByFirebaseUidOrThrow(firebaseUid);
    await this.contasService.remove(user.id, id);
    return { removed: true };
  }
}
