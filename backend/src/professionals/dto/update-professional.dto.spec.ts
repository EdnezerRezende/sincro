import { plainToInstance } from 'class-transformer';
import { validate } from 'class-validator';
import { UpdateProfessionalDto } from './update-professional.dto';

describe('UpdateProfessionalDto', () => {
  it('accepts a partial body with only ativo (reactivation)', async () => {
    const dto = plainToInstance(UpdateProfessionalDto, { ativo: true });
    const errors = await validate(dto, { whitelist: true, forbidNonWhitelisted: true });
    expect(errors).toHaveLength(0);
  });

  it('still validates provided fields', async () => {
    const dto = plainToInstance(UpdateProfessionalDto, { telefone: '11999' });
    const errors = await validate(dto, { whitelist: true, forbidNonWhitelisted: true });
    expect(errors.map((e) => e.property)).toEqual(['telefone']);
  });

  it('rejects unknown fields', async () => {
    const dto = plainToInstance(UpdateProfessionalDto, { foo: 1 });
    const errors = await validate(dto, { whitelist: true, forbidNonWhitelisted: true });
    expect(errors.map((e) => e.property)).toEqual(['foo']);
  });
});
