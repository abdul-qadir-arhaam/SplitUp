import { Router } from 'express';
import { z } from 'zod';
import { inMemoryUsers } from '../users/store.js';
import { normalizePhoneE164, isValidE164 } from '../users/phone.js';
import { ValidationError } from '../../lib/errors.js';

export const contactsRouter = Router();

const lookupSchema = z.object({
  phones: z.array(z.string()).max(500),
});

// POST /v1/contacts/lookup
contactsRouter.post('/contacts/lookup', (req, res) => {
  const body = lookupSchema.parse(req.body);

  // Normalize all incoming phones
  const normalizedPhones = new Set<string>();
  for (const raw of body.phones) {
    try {
      if (isValidE164(raw)) {
        normalizedPhones.add(normalizePhoneE164(raw));
      }
    } catch {
      // Ignore unparseable entries
    }
  }

  const matches: Array<{
    phone: string;
    userId: string;
    name: string;
    photoUrl?: string | null;
  }> = [];

  for (const user of inMemoryUsers.values()) {
    // Only real users are returned (DATABASE.md: placeholders never appear as is_user)
    if (!user.isPlaceholder && user.status === 'ACTIVE' && normalizedPhones.has(user.phoneE164)) {
      matches.push({
        phone: user.phoneE164,
        userId: user.id,
        name: user.name,
        photoUrl: user.photoUrl,
      });
    }
  }

  res.json({
    data: {
      matches,
    },
  });
});
