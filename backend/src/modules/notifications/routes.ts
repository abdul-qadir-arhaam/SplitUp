import { Router } from 'express';
import { notificationsStore } from './store.js';

export const notificationsRouter = Router();

// GET /v1/notifications
notificationsRouter.get('/notifications', (req, res) => {
  const userId = req.user?.id || 'usr_arhaam';
  const notifications = notificationsStore.listForUser(userId);
  const unreadCount = notificationsStore.getUnreadCount(userId);

  res.json({
    data: notifications,
    unreadCount,
  });
});

// PATCH /v1/notifications/:id/read
notificationsRouter.patch('/notifications/:id/read', (req, res) => {
  const userId = req.user?.id || 'usr_arhaam';
  const success = notificationsStore.markRead(req.params.id, userId);
  res.json({ success });
});

// POST /v1/notifications/mark-all-read
notificationsRouter.post('/notifications/mark-all-read', (req, res) => {
  const userId = req.user?.id || 'usr_arhaam';
  notificationsStore.markAllRead(userId);
  res.json({ success: true });
});
