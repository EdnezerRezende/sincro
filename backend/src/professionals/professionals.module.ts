import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { UsersModule } from '../users/users.module';
import { ProfessionalsService } from './professionals.service';
import { ProfessionalsController } from './professionals.controller';
import { AdminProfessionalsController } from './admin-professionals.controller';
import { AdminGuard } from './admin.guard';

@Module({
  imports: [AuthModule, UsersModule],
  providers: [ProfessionalsService, AdminGuard],
  controllers: [ProfessionalsController, AdminProfessionalsController],
})
export class ProfessionalsModule {}
