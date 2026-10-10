import { ValidationError } from '../../lib/errors.js';

/**
 * Normalizes a phone number to standard E.164 format (+[country code][number]).
 * Strips whitespace, hyphens, and brackets.
 * Defaults 10-digit Indian numbers (or numbers starting with 0) to +91.
 */
export function normalizePhoneE164(raw: string): string {
  if (!raw || typeof raw !== 'string') {
    throw new ValidationError('Phone number is required');
  }

  // Remove whitespace, dashes, parentheses, dots
  let cleaned = raw.trim().replace(/[\s\-\(\)\.]/g, '');

  // If starts with 0 and followed by 10 digits (common Indian dial format: 09876543210)
  if (/^0[6-9]\d{9}$/.test(cleaned)) {
    cleaned = '+91' + cleaned.slice(1);
  }
  // If 10 digits starting with 6-9, assume Indian mobile number
  else if (/^[6-9]\d{9}$/.test(cleaned)) {
    cleaned = '+91' + cleaned;
  }
  // If starts with 91 and followed by 10 digits without plus
  else if (/^91[6-9]\d{9}$/.test(cleaned)) {
    cleaned = '+' + cleaned;
  }
  // If starts with 00 (international call prefix), replace with +
  else if (cleaned.startsWith('00')) {
    cleaned = '+' + cleaned.slice(2);
  }
  // If does not start with +, but is just digits
  else if (!cleaned.startsWith('+')) {
    cleaned = '+' + cleaned;
  }

  // Standard E.164 format: + followed by 8 to 15 digits
  const e164Regex = /^\+[1-9]\d{7,14}$/;
  if (!e164Regex.test(cleaned)) {
    throw new ValidationError(`Invalid phone number format: "${raw}". Must be a valid E.164 phone number.`);
  }

  return cleaned;
}

export function isValidE164(raw: string): boolean {
  try {
    normalizePhoneE164(raw);
    return true;
  } catch {
    return false;
  }
}
