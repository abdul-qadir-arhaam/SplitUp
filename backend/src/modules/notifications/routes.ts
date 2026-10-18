import { Router } from 'express';
import { notificationsStore } from './store.js';

export const notificationsRouter = Router();

// GET /v1/notifications
notificationsRouter.get('/notifications', async (req, res, next) => {
  try {
    const userId = req.user?.id || 'usr_arhaam';
    const notifications = await notificationsStore.listForUser(userId);
    const unreadCount = await notificationsStore.getUnreadCount(userId);

    res.json({
      data: notifications,
      unreadCount,
    });
  } catch (err) {
    next(err);
  }
});

// PATCH /v1/notifications/:id/read
notificationsRouter.patch('/notifications/:id/read', async (req, res, next) => {
  try {
    const userId = req.user?.id || 'usr_arhaam';
    const success = await notificationsStore.markRead(req.params.id, userId);
    res.json({ success });
  } catch (err) {
    next(err);
  }
});

// GET /v1/notifications/unread-count
notificationsRouter.get('/notifications/unread-count', async (req, res, next) => {
  try {
    const userId = req.user?.id || 'usr_arhaam';
    const unreadCount = await notificationsStore.getUnreadCount(userId);
    res.json({ unreadCount });
  } catch (err) {
    next(err);
  }
});

// DELETE /v1/notifications/:id (Dismiss single notification)
notificationsRouter.delete('/notifications/:id', async (req, res, next) => {
  try {
    const userId = req.user?.id || 'usr_arhaam';
    const success = await notificationsStore.dismiss(req.params.id, userId);
    res.json({ success });
  } catch (err) {
    next(err);
  }
});

// DELETE /v1/notifications (Dismiss all notifications for caller)
notificationsRouter.delete('/notifications', async (req, res, next) => {
  try {
    const userId = req.user?.id || 'usr_arhaam';
    await notificationsStore.dismissAll(userId);
    res.json({ success: true });
  } catch (err) {
    next(err);
  }
});
