import { ArrayNotEmpty, IsArray, IsBoolean, IsLatitude, IsLongitude, IsOptional, IsString, Length, Matches } from 'class-validator';

/** PATCH parcial: todo campo é opcional; os presentes são validados como no create. */
export class UpdateProfessionalDto {
  @IsOptional()
  @IsString()
  @Length(1, 100)
  nome?: string;

  @IsOptional()
  @IsArray()
  @ArrayNotEmpty()
  @IsString({ each: true })
  tags?: string[];

  @IsOptional()
  @IsString()
  @Length(1, 100)
  cidade?: string;

  @IsOptional()
  @IsLatitude()
  latitude?: number;

  @IsOptional()
  @IsLongitude()
  longitude?: number;

  @IsOptional()
  @IsString()
  @Length(8, 20)
  @Matches(/^\+\d{10,15}$/, {
    message: 'telefone must start with + followed by the country code and 10-15 digits, e.g. +5511999999999',
  })
  telefone?: string;

  @IsOptional()
  @IsString()
  @Length(1, 500)
  bio?: string;

  @IsOptional()
  @IsBoolean()
  ativo?: boolean;
}
