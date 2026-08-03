import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { SensoryProfileModule } from '../sensory-profile/sensory-profile.module';
import { NotificationService } from './notification.service';

@Module({
  imports: [AuthModule, SensoryProfileModule],
  providers: [NotificationService],
  exports: [NotificationService],
})
export class NotificationsModule {}
