import { haversineDistanceKm } from './geo';

describe('haversineDistanceKm', () => {
  it('returns 0 for identical coordinates', () => {
    expect(haversineDistanceKm(-23.5, -46.6, -23.5, -46.6)).toBe(0);
  });

  it('returns approximately 111km for one degree of latitude apart at the equator', () => {
    const distancia = haversineDistanceKm(0, 0, 1, 0);
    expect(distancia).toBeGreaterThan(110);
    expect(distancia).toBeLessThan(112);
  });

  it('is symmetric', () => {
    const ab = haversineDistanceKm(-23.5, -46.6, -22.9, -43.2);
    const ba = haversineDistanceKm(-22.9, -43.2, -23.5, -46.6);
    expect(ab).toBeCloseTo(ba, 6);
  });
});
