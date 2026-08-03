import { Injectable } from '@nestjs/common';
import { createCipheriv, createDecipheriv, randomBytes } from 'crypto';

const IV_LENGTH_BYTES = 12;
const AUTH_TAG_LENGTH_BYTES = 16;

@Injectable()
export class TokenCryptoService {
  private readonly key: Buffer;

  constructor() {
    const keyBase64 = process.env.TOKEN_ENCRYPTION_KEY;
    if (!keyBase64) {
      throw new Error(
        'TOKEN_ENCRYPTION_KEY is not set. Generate one with: ' +
          `node -e "console.log(require('crypto').randomBytes(32).toString('base64'))"`,
      );
    }
    this.key = Buffer.from(keyBase64, 'base64');
    if (this.key.length !== 32) {
      throw new Error('TOKEN_ENCRYPTION_KEY must decode to exactly 32 bytes (AES-256).');
    }
  }

  encrypt(plaintext: string): string {
    const iv = randomBytes(IV_LENGTH_BYTES);
    const cipher = createCipheriv('aes-256-gcm', this.key, iv);
    const ciphertext = Buffer.concat([cipher.update(plaintext, 'utf8'), cipher.final()]);
    const authTag = cipher.getAuthTag();
    return Buffer.concat([iv, authTag, ciphertext]).toString('base64');
  }

  decrypt(encoded: string): string {
    const buffer = Buffer.from(encoded, 'base64');
    const iv = buffer.subarray(0, IV_LENGTH_BYTES);
    const authTag = buffer.subarray(IV_LENGTH_BYTES, IV_LENGTH_BYTES + AUTH_TAG_LENGTH_BYTES);
    const ciphertext = buffer.subarray(IV_LENGTH_BYTES + AUTH_TAG_LENGTH_BYTES);
    const decipher = createDecipheriv('aes-256-gcm', this.key, iv);
    decipher.setAuthTag(authTag);
    return Buffer.concat([decipher.update(ciphertext), decipher.final()]).toString('utf8');
  }
}
