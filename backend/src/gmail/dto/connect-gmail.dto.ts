import { IsString, MinLength } from 'class-validator';

export class ConnectGmailDto {
  @IsString()
  @MinLength(1)
  serverAuthCode: string;
}
