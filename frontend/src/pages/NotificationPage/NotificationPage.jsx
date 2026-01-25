import { useEffect, useMemo } from 'react';
import { useNavigate } from 'react-router-dom';
import { getNotifications, markAsRead } from '../../api/notificationApi';
import { useAuth } from '../../hooks/useAuth';
import { useApiQuery } from '../../hooks/useApiQuery';
import { useApiMutation } from '../../hooks/useApiMutation';
import PageHeader from '../../components/common/PageHeader';
import LoadingState from '../../components/common/LoadingState';
import ApiError from '../../components/common/ApiError';
import EmptyState from '../../components/common/EmptyState';
import ApiDebug from '../../components/common/ApiDebug';
import './NotificationPage.css';

/**
 * NotificationPage
 * API: GET /api/v1/notifications
 * API: PATCH /api/v1/notifications/:id
 * 
 * Displays user notifications with read/unread status
 * Uses shared hooks for consistent data fetching and auth
 */
export default function NotificationPage() {
    const navigate = useNavigate();
    const { isAuthenticated, requireAuth } = useAuth();

    // Auth guard
    useEffect(() => {
        requireAuth(navigate, '/notifications');
    }, [requireAuth, navigate]);

    // Fetch notifications using shared hook
    const { data: notifications, loading, error, mutate } = useApiQuery(
        isAuthenticated ? 'notifications' : null,
        getNotifications
    );

    // Mark as read mutation with optimistic update
    const { mutate: markRead, loading: markingRead } = useApiMutation(markAsRead, {
        successMessage: 'Marked as read',
        errorMessage: 'Failed to mark as read',
    });

    const handleMarkAsRead = async (id) => {
        // Optimistic update
        mutate(
            notifications?.map(n => n.id === id ? { ...n, read: true } : n),
            false // Don't revalidate yet
        );
        
        const result = await markRead(id);
        if (result) {
            // Revalidate on success
            mutate();
        } else {
            // Revert on failure
            mutate();
        }
    };

    // Computed values
    const notificationsList = useMemo(() => notifications || [], [notifications]);
    const unreadCount = useMemo(() => notificationsList.filter(n => !n.read).length, [notificationsList]);
    const unreadNotifications = useMemo(() => notificationsList.filter(n => !n.read), [notificationsList]);
    const readNotifications = useMemo(() => notificationsList.filter(n => n.read), [notificationsList]);

    // Get notification icon based on type
    const getNotificationIcon = (type) => {
        const icons = {
            order_shipped: '📦',
            order_completed: '✅',
            order_placed: '🛒',
            order_processing: '⚙️',
            review_reminder: '⭐',
            promotion: '🎉',
            cart_reminder: '🛍️',
            email: '📧',
            sms: '📱',
        };
        return icons[type] || '🔔';
    };

    // Format date
    const formatDate = (dateString) => {
        if (!dateString) return '';
        try {
            return new Date(dateString).toLocaleString();
        } catch {
            return '';
        }
    };

    // Auth gate
    if (!isAuthenticated) {
        return (
            <div className="page container">
                <PageHeader title="Notifications" backLink="/" backText="← Back to Home" />
                <EmptyState message="Please log in to view notifications" icon="🔒" />
            </div>
        );
    }

    return (
        <div className="page container">
            <PageHeader 
                title="Notifications" 
                backLink="/" 
                backText="← Back to Home"
                apiLabel={`API: GET /api/v1/notifications • ${notificationsList.length} items`}
            />

            {/* Loading State */}
            {loading && <LoadingState message="Loading notifications..." variant="list" count={3} />}

            {/* Error State */}
            {!loading && error && (
                <ApiError error={error} endpoint="GET /api/v1/notifications" />
            )}

            {/* Empty State */}
            {!loading && !error && notificationsList.length === 0 && (
                <EmptyState message="No notifications" icon="🔔" />
            )}

            {/* Notifications Content */}
            {!loading && !error && notificationsList.length > 0 && (
                <>
                    {/* Summary */}
                    <div className="notification-summary">
                        <p>
                            {unreadCount > 0 ? (
                                <><strong>{unreadCount}</strong> unread notification{unreadCount !== 1 ? 's' : ''}</>
                            ) : (
                                'All caught up! 🎉'
                            )}
                        </p>
                    </div>

                    {/* Unread Notifications */}
                    {unreadNotifications.length > 0 && (
                        <div className="notification-section unread">
                            <h3>Unread</h3>
                            {unreadNotifications.map(notification => (
                                <div key={notification.id} className="notification-item unread">
                                    <div className="notification-content">
                                        <div className="notification-body">
                                            <div className="notification-header">
                                                <span className="notification-icon">
                                                    {getNotificationIcon(notification.type)}
                                                </span>
                                                <h4 className="notification-title">
                                                    {notification.title || notification.message}
                                                </h4>
                                            </div>
                                            {notification.title && notification.message !== notification.title && (
                                                <p className="notification-message">{notification.message}</p>
                                            )}
                                            <p className="notification-time">
                                                {formatDate(notification.created_at)}
                                            </p>
                                        </div>
                                        <div className="notification-actions">
                                            <button
                                                className="primary"
                                                onClick={() => handleMarkAsRead(notification.id)}
                                                disabled={markingRead}
                                            >
                                                {markingRead ? 'Marking...' : 'Mark as Read'}
                                            </button>
                                        </div>
                                    </div>
                                </div>
                            ))}
                        </div>
                    )}

                    {/* Read Notifications */}
                    {readNotifications.length > 0 && (
                        <div className="notification-section read">
                            <h3>Read</h3>
                            {readNotifications.map(notification => (
                                <div key={notification.id} className="notification-item read">
                                    <div className="notification-body">
                                        <div className="notification-header">
                                            <span className="notification-icon">
                                                {getNotificationIcon(notification.type)}
                                            </span>
                                            <h4 className="notification-title">
                                                {notification.title || notification.message}
                                            </h4>
                                        </div>
                                        {notification.title && notification.message !== notification.title && (
                                            <p className="notification-message">{notification.message}</p>
                                        )}
                                        <p className="notification-time">
                                            {formatDate(notification.created_at)}
                                        </p>
                                    </div>
                                </div>
                            ))}
                        </div>
                    )}
                </>
            )}

            {/* API Debug */}
            <ApiDebug data={notifications} />
        </div>
    );
}
