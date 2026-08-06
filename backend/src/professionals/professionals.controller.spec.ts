import { BadRequestException } from '@nestjs/common';
import { ProfessionalsController } from './professionals.controller';

describe('ProfessionalsController', () => {
  it('rejects a search missing lat/lng', async () => {
    const service = { search: jest.fn() };
    const controller = new ProfessionalsController(service as any);

    await expect(controller.search(undefined as any, undefined as any, undefined)).rejects.toThrow(
      BadRequestException,
    );
    expect(service.search).not.toHaveBeenCalled();
  });

  it('rejects a search with non-numeric lat/lng', async () => {
    const service = { search: jest.fn() };
    const controller = new ProfessionalsController(service as any);

    await expect(controller.search('abc', '10', undefined)).rejects.toThrow(BadRequestException);
    expect(service.search).not.toHaveBeenCalled();
  });

  it('rejects a search with empty-string lat/lng instead of silently coercing to (0, 0)', async () => {
    const service = { search: jest.fn() };
    const controller = new ProfessionalsController(service as any);

    await expect(controller.search('', '', undefined)).rejects.toThrow(BadRequestException);
    expect(service.search).not.toHaveBeenCalled();
  });

  it('rejects a search with whitespace-only lat/lng', async () => {
    const service = { search: jest.fn() };
    const controller = new ProfessionalsController(service as any);

    await expect(controller.search('   ', '  ', undefined)).rejects.toThrow(BadRequestException);
    expect(service.search).not.toHaveBeenCalled();
  });

  it('rejects a search where only lng is an empty string', async () => {
    const service = { search: jest.fn() };
    const controller = new ProfessionalsController(service as any);

    await expect(controller.search('-23.5', '', undefined)).rejects.toThrow(BadRequestException);
    expect(service.search).not.toHaveBeenCalled();
  });

  it('parses tags from a comma-separated query string, trimming and dropping empties', async () => {
    const service = { search: jest.fn().mockResolvedValue([]) };
    const controller = new ProfessionalsController(service as any);

    await controller.search('-23.5', '-46.6', ' TEA ,TDAH ,');

    expect(service.search).toHaveBeenCalledWith(-23.5, -46.6, ['TEA', 'TDAH']);
  });

  it('omits tags when the query param is absent', async () => {
    const service = { search: jest.fn().mockResolvedValue([]) };
    const controller = new ProfessionalsController(service as any);

    await controller.search('-23.5', '-46.6', undefined);

    expect(service.search).toHaveBeenCalledWith(-23.5, -46.6, undefined);
  });
});
