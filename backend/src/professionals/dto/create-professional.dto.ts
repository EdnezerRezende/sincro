import { ArrayNotEmpty, IsArray, IsLatitude, IsLongitude, IsString, Length, Matches } from 'class-validator';

export class CreateProfessionalDto {
  @IsString()
  @Length(1, 100)
  nome: string;

  @IsArray()
  @ArrayNotEmpty()
  @IsString({ each: true })
  tags: string[];

  @IsString()
  @Length(1, 100)
  cidade: string;

  @IsLatitude()
  latitude: number;

  @IsLongitude()
  longitude: number;

  @IsString()
  @Length(8, 20)
  @Matches(/^\+\d{10,15}$/, {
    message: 'telefone must start with + followed by the country code and 10-15 digits, e.g. +5511999999999',
  })
  telefone: string;

  @IsString()
  @Length(1, 500)
  bio: string;
}
