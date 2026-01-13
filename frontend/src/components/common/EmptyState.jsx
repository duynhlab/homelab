/**
 * EmptyState Component
 * Generic empty state display
 * API-agnostic
 */
export default function EmptyState({ message = 'No items found', icon = '📦' }) {
    return (
        <div className="empty-box">
            <div style={{ fontSize: '3rem', marginBottom: '1rem' }}>{icon}</div>
            <p>{message}</p>
        </div>
    );
}
