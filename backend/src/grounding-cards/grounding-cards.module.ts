import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { UsersModule } from '../users/users.module';
import { AdminGuard } from '../common/admin.guard';
import { GroundingCardsService } from './grounding-cards.service';
import { GroundingCardsController } from './grounding-cards.controller';
import { AdminGroundingCardsController } from './admin-grounding-cards.controller';

@Module({
  imports: [AuthModule, UsersModule],
  providers: [GroundingCardsService, AdminGuard],
  controllers: [GroundingCardsController, AdminGroundingCardsController],
})
export class GroundingCardsModule {}
