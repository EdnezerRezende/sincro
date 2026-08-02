import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { UsersModule } from '../users/users.module';
import { EmergencyService } from './emergency.service';
import { EmergencyController } from './emergency.controller';

@Module({
  imports: [AuthModule, UsersModule],
  providers: [EmergencyService],
  controllers: [EmergencyController],
})
export class EmergencyModule {}
