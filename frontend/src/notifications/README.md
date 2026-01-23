# Notifications Module

This folder is a **placeholder** for future integration with the backend **notification microservice**.

## Current State

Toast notifications are triggered **locally** via the `useToast()` hook:

```jsx
import { useToast } from '../components/common/ToastProvider';

function MyComponent() {
    const { notify } = useToast();
    
    // Trigger a toast
    notify('success', 'Item added to cart');
    notify('error', 'Failed to save');
    notify('info', 'You already reviewed this product');
}
```

## Future Integration

To consume real-time notifications from the notification microservice:

1. **Create a connector** (e.g., `notificationService.js`) that:
   - Opens a WebSocket / SSE connection to the notification service
   - Listens for incoming events
   - Calls `notify(type, message)` for each event

2. **Wire it at app root** (similar to `ToastProvider`):

```jsx
// Example: frontend/src/notifications/NotificationConnector.jsx
import { useEffect } from 'react';
import { useToast } from '../components/common/ToastProvider';

export function NotificationConnector({ children }) {
    const { notify } = useToast();

    useEffect(() => {
        // Connect to notification service
        const ws = new WebSocket('ws://notification-svc/subscribe');
        
        ws.onmessage = (event) => {
            const data = JSON.parse(event.data);
            notify(data.type || 'info', data.message);
        };

        return () => ws.close();
    }, [notify]);

    return children;
}
```

3. **Wrap in main.jsx**:

```jsx
<ToastProvider>
    <NotificationConnector>
        <App />
    </NotificationConnector>
</ToastProvider>
```

## API Reference

### `notify(type, message, options?)`

| Parameter | Type | Description |
|-----------|------|-------------|
| `type` | `'success' \| 'error' \| 'info'` | Notification severity |
| `message` | `string` | Text to display |
| `options.duration` | `number` | Auto-dismiss time in ms (default: 4000, 0 = no auto-dismiss) |

### Returns
- `id: number` - Can be used with `dismiss(id)` for manual dismissal

## Related Files

- `components/common/ToastProvider.jsx` - Context + hook
- `components/common/ToastViewport.jsx` - UI component
- `components/common/toast.css` - Styles
