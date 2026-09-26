import { Module, forwardRef } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { UsersModule } from '../users/users.module';
import { CryptoModule } from '../crypto/crypto.module';
import { GmailOAuthService } from './gmail-oauth.service';
import { GmailApiClient } from './gmail-api-client.service';
import { GmailConnectionsService } from './gmail-connections.service';
import { GmailController } from './gmail.controller';

// forwardRef: UsersService chama de volta GmailConnectionsService.disconnect() ao excluir a
// conta (DELETE /users/me), então os dois módulos dependem um do outro.
@Module({
  imports: [AuthModule, forwardRef(() => UsersModule), CryptoModule],
  providers: [GmailOAuthService, GmailApiClient, GmailConnectionsService],
  controllers: [GmailController],
  exports: [GmailOAuthService, GmailApiClient, GmailConnectionsService],
})
export class GmailModule {}
