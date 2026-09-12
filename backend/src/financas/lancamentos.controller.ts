import { Body, Controller, Get, Param, Patch, Post, Query, UseGuards } from '@nestjs/common';
import { FirebaseAuthGuard } from '../auth/firebase-auth.guard';
import { CurrentFirebaseUid } from '../common/current-firebase-uid.decorator';
import { UsersService } from '../users/users.service';
import { CreateLancamentoDto } from './dto/create-lancamento.dto';
import { UpdateLancamentoDto } from './dto/update-lancamento.dto';
import { LancamentosService } from './lancamentos.service';

@UseGuards(FirebaseAuthGuard)
@Controller('financas/lancamentos')
export class LancamentosController {
  constructor(
    private readonly lancamentosService: LancamentosService,
    private readonly usersService: UsersService,
  ) {}

  @Get()
  async list(
    @CurrentFirebaseUid() firebaseUid: string,
    @Query('status') status?: string,
    @Query('mes') mes?: string,
  ) {
    const user = await this.usersService.getByFirebaseUidOrThrow(firebaseUid);
    return this.lancamentosService.list(user.id, { status, mes });
  }

  @Post()
  async create(@CurrentFirebaseUid() firebaseUid: string, @Body() dto: CreateLancamentoDto) {
    const user = await this.usersService.getByFirebaseUidOrThrow(firebaseUid);
    return this.lancamentosService.createManual(user.id, dto);
  }

  @Patch(':id')
  async update(
    @CurrentFirebaseUid() firebaseUid: string,
    @Param('id') id: string,
    @Body() dto: UpdateLancamentoDto,
  ) {
    const user = await this.usersService.getByFirebaseUidOrThrow(firebaseUid);
    return this.lancamentosService.update(user.id, id, dto);
  }
}
