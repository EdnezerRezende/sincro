import { IsString, Length } from 'class-validator';

export class UpsertUserDto {
  @IsString()
  @Length(1, 100)
  nome: string;
}
