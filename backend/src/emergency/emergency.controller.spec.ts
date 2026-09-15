import { EmergencyController } from './emergency.controller';

describe('EmergencyController', () => {
  it('delegates POST /emergency/messages to the service with contactIds and template', async () => {
    const service = { buildMessages: jest.fn().mockResolvedValue([{ contactId: 'c1' }]), buildMessage: jest.fn() };
    const controller = new EmergencyController(service as any);

    const result = await controller.buildMessages('fb1', { contactIds: ['c1'], template: 'Oi {primeiro nome}' });

    expect(service.buildMessages).toHaveBeenCalledWith('fb1', ['c1'], 'Oi {primeiro nome}');
    expect(result).toEqual([{ contactId: 'c1' }]);
  });
});
