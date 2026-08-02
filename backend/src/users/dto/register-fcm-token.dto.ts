import { IsString, MinLength } from 'class-validator';

export class RegisterFcmTokenDto {
  @IsString()
  @MinLength(1)
  fcmToken: string;
}
