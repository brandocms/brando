// RFC 6238 codes (SHA-1, 6 digits, 30 seconds), as an authenticator app
// computes them from the Base32 setup key the admin shows.
import { createHmac } from 'node:crypto'

const ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567'

const decodeBase32 = (text) => {
  const bits = [...text.replace(/[\s=]/g, '').toUpperCase()]
    .map((char) => ALPHABET.indexOf(char).toString(2).padStart(5, '0'))
    .join('')
  const bytes = []
  for (let i = 0; i + 8 <= bits.length; i += 8) bytes.push(parseInt(bits.slice(i, i + 8), 2))
  return Buffer.from(bytes)
}

// `step` counts 30-second steps from now: 1 is the next code, which the server
// accepts too, and which a code already used in this step does not block.
export const totp = (secret, step = 0) => {
  const counter = Buffer.alloc(8)
  counter.writeBigUInt64BE(BigInt(Math.floor(Date.now() / 30000) + step))
  const hmac = createHmac('sha1', decodeBase32(secret)).update(counter).digest()
  const offset = hmac[hmac.length - 1] & 0xf
  return ((hmac.readUInt32BE(offset) & 0x7fffffff) % 1000000).toString().padStart(6, '0')
}
