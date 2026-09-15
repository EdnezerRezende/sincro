import { ArrayMaxSize, ArrayMinSize, IsArray, IsOptional, IsString, IsUUID, Length } from 'class-validator';

export class BuildEmergencyMessagesDto {
  @IsArray()
  @ArrayMinSize(1)
  @ArrayMaxSize(10)
  @IsUUID('all', { each: true })
  contactIds: string[];

  @IsOptional()
  @IsString()
  @Length(1, 300)
  template?: string;
}
