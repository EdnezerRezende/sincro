import { IsUUID } from 'class-validator';

export class BuildEmergencyMessageDto {
  @IsUUID()
  contactId: string;
}
