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

// GET /v1/notifications/unread-count
notificationsRouter.get('/notifications/unread-count', (req, res) => {
  const userId = req.user?.id || 'usr_arhaam';
  const unreadCount = notificationsStore.getUnreadCount(userId);
  res.json({ unreadCount });
});

// DELETE /v1/notifications/:id (Dismiss single notification)
notificationsRouter.delete('/notifications/:id', (req, res) => {
  const userId = req.user?.id || 'usr_arhaam';
  const success = notificationsStore.dismiss(req.params.id, userId);
  res.json({ success });
});

// DELETE /v1/notifications (Dismiss all notifications for caller)
notificationsRouter.delete('/notifications', (req, res) => {
  const userId = req.user?.id || 'usr_arhaam';
  notificationsStore.dismissAll(userId);
  res.json({ success: true });
});

