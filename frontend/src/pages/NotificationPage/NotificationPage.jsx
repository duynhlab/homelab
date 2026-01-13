import { useState, useEffect } from 'react';
import { Link } from 'react-router-dom';
import { getNotifications, markAsRead } from '../../api/notificationApi';
import EmptyState from '../../components/common/EmptyState';

/**
 * NotificationPage
 * API: GET /api/v2/notifications
 * API: PATCH /api/v2/notifications/:id
 * 
 * Displays user notifications with read/unread status
 */
export default function NotificationPage() {
    const [notifications, setNotifications] = useState([]);
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState(null);
    const [actionLoading, setActionLoading] = useState(null);

    const fetchNotifications = async () => {
        setLoading(true);
        setError(null);
        try {
            const result = await getNotifications();
            setNotifications(result);
            console.log('[API] GET /api/v2/notifications:', result);
        } catch (err) {
            setError(err.message);
            console.error('[API ERROR]', err);
        } finally {
            setLoading(false);
        }
    };

    useEffect(() => {
        fetchNotifications();
    }, []);

    const handleMarkAsRead = async (id) => {
        setActionLoading(id);
        try {
            await markAsRead(id);
            console.log('[API] PATCH /api/v2/notifications/' + id);
            // Update local state
            setNotifications(prev =>
                prev.map(n => n.id === id ? { ...n, read: true } : n)
            );
        } catch (err) {
            console.error('[API ERROR]', err);
        } finally {
            setActionLoading(null);
        }
    };

    const unreadCount = notifications.filter(n => !n.read).length;

    // Group notifications by read status
    const unreadNotifications = notifications.filter(n => !n.read);
    const readNotifications = notifications.filter(n => n.read);

    // Get notification icon based on type
    const getNotificationIcon = (type) => {
        const icons = {
            order_shipped: '📦',
            order_completed: '✅',
            order_placed: '🛒',
            order_processing: '⚙️',
            review_reminder: '⭐',
            promotion: '🎉',
            cart_reminder: '🛍️'
        };
        return icons[type] || '🔔';
    };

    if (loading) return <div className="loading">Loading notifications...</div>;
    if (error) return <div className="error">Error: {error}</div>;

    return (
        <div className="page container">
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '2rem' }}>
                <h2>Notifications</h2>
                <Link to="/" className="back-link">← Back to Home</Link>
            </div>

            <p className="api-label">API: GET /api/v2/notifications</p>

            {notifications.length === 0 ? (
                <EmptyState message="No notifications" icon="🔔" />
            ) : (
                <>
                    {/* Summary */}
                    <div style={{ marginBottom: '1.5rem', padding: '1rem', background: '#f5f5f5', borderRadius: '8px' }}>
                        <p style={{ margin: 0, color: '#666' }}>
                            {unreadCount > 0 ? (
                                <>
                                    <strong>{unreadCount}</strong> unread notification{unreadCount !== 1 ? 's' : ''}
                                </>
                            ) : (
                                'All caught up! 🎉'
                            )}
                        </p>
                    </div>

                    {/* Unread Notifications */}
                    {unreadNotifications.length > 0 && (
                        <div style={{ marginBottom: '2rem' }}>
                            <h3 style={{ marginBottom: '1rem', color: '#333' }}>Unread</h3>
                            {unreadNotifications.map(notification => (
                                <div
                                    key={notification.id}
                                    style={{
                                        padding: '1.5rem',
                                        marginBottom: '1rem',
                                        border: '2px solid #4CAF50',
                                        borderRadius: '8px',
                                        background: '#f0fff4'
                                    }}
                                >
                                    <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'start' }}>
                                        <div style={{ flex: 1 }}>
                                            <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem', marginBottom: '0.5rem' }}>
                                                <span style={{ fontSize: '1.5rem' }}>
                                                    {getNotificationIcon(notification.type)}
                                                </span>
                                                <h4 style={{ margin: 0 }}>{notification.title}</h4>
                                            </div>
                                            <p style={{ color: '#555', margin: '0.5rem 0' }}>{notification.message}</p>
                                            <p style={{ color: '#888', fontSize: '0.85rem', margin: 0 }}>
                                                {new Date(notification.created_at).toLocaleString()}
                                            </p>
                                        </div>
                                        <button
                                            onClick={() => handleMarkAsRead(notification.id)}
                                            disabled={actionLoading === notification.id}
                                            style={{
                                                padding: '0.5rem 1rem',
                                                background: '#4CAF50',
                                                color: 'white',
                                                border: 'none',
                                                borderRadius: '4px',
                                                cursor: 'pointer',
                                                fontSize: '0.85rem'
                                            }}
                                        >
                                            {actionLoading === notification.id ? 'Marking...' : 'Mark as Read'}
                                        </button>
                                    </div>
                                </div>
                            ))}
                        </div>
                    )}

                    {/* Read Notifications */}
                    {readNotifications.length > 0 && (
                        <div>
                            <h3 style={{ marginBottom: '1rem', color: '#888' }}>Read</h3>
                            {readNotifications.map(notification => (
                                <div
                                    key={notification.id}
                                    style={{
                                        padding: '1.5rem',
                                        marginBottom: '1rem',
                                        border: '1px solid #ddd',
                                        borderRadius: '8px',
                                        background: '#fafafa',
                                        opacity: 0.7
                                    }}
                                >
                                    <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem', marginBottom: '0.5rem' }}>
                                        <span style={{ fontSize: '1.5rem' }}>
                                            {getNotificationIcon(notification.type)}
                                        </span>
                                        <h4 style={{ margin: 0, color: '#888' }}>{notification.title}</h4>
                                    </div>
                                    <p style={{ color: '#777', margin: '0.5rem 0' }}>{notification.message}</p>
                                    <p style={{ color: '#999', fontSize: '0.85rem', margin: 0 }}>
                                        {new Date(notification.created_at).toLocaleString()}
                                    </p>
                                </div>
                            ))}
                        </div>
                    )}
                </>
            )}

            {/* API Debug */}
            <details style={{ marginTop: '2rem' }}>
                <summary>API Response Debug</summary>
                <pre style={{ background: '#000', padding: '1rem', overflow: 'auto', fontSize: '0.75rem' }}>
                    {JSON.stringify(notifications, null, 2)}
                </pre>
            </details>
        </div>
    );
}
