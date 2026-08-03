import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { UsersModule } from '../users/users.module';
import { SensoryProfileService } from './sensory-profile.service';
import { SensoryProfileController } from './sensory-profile.controller';

@Module({
  imports: [AuthModule, UsersModule],
  providers: [SensoryProfileService],
  controllers: [SensoryProfileController],
  exports: [SensoryProfileService],
})
export class SensoryProfileModule {}
