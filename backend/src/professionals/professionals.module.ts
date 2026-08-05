import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { ProfessionalsService } from './professionals.service';
import { ProfessionalsController } from './professionals.controller';

@Module({
  imports: [AuthModule],
  providers: [ProfessionalsService],
  controllers: [ProfessionalsController],
})
export class ProfessionalsModule {}
