import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { UsersModule } from '../users/users.module';
import { GroundingCardsService } from './grounding-cards.service';
import { GroundingCardsController } from './grounding-cards.controller';

@Module({
  imports: [AuthModule, UsersModule],
  providers: [GroundingCardsService],
  controllers: [GroundingCardsController],
})
export class GroundingCardsModule {}
