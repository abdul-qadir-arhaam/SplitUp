export interface User {
  id: string;
  firebaseUid?: string | null;
  phoneE164: string;
  name: string;
  email?: string | null;
  photoUrl?: string | null;
  isPlaceholder: boolean;
  status: 'ACTIVE' | 'BLOCKED' | 'DELETED';
  createdBy?: string | null;
  createdAt: string;
  updatedAt: string;
}

export interface MergeSummary {
  merged: boolean;
  placeholderId?: string;
  realUserId?: string;
  expenseCount: number;
  totalPaise: number;
  affectedLedgerIds: string[];
}
