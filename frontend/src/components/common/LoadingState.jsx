import { Skeleton } from './Skeleton';

/**
 * LoadingState Component
 * Standard loading UI with optional message
 * 
 * Usage:
 *   <LoadingState />
 *   <LoadingState message="Loading orders..." />
 *   <LoadingState variant="card" />
 */
export default function LoadingState({ 
    message = 'Loading...', 
    variant = 'default',
    count = 3 
}) {
    if (variant === 'card') {
        return (
            <div className="loading-cards">
                {Array.from({ length: count }).map((_, i) => (
                    <div key={i} className="card loading-card">
                        <Skeleton width="60%" height="1.25rem" style={{ marginBottom: '0.75rem' }} />
                        <Skeleton width="100%" height="1rem" style={{ marginBottom: '0.5rem' }} />
                        <Skeleton width="80%" height="1rem" />
                    </div>
                ))}
            </div>
        );
    }

    if (variant === 'list') {
        return (
            <div className="loading-list">
                {Array.from({ length: count }).map((_, i) => (
                    <div key={i} className="loading-list-item">
                        <Skeleton width="100%" height="3rem" style={{ marginBottom: '0.5rem' }} />
                    </div>
                ))}
            </div>
        );
    }

    // Default: simple text loading
    return (
        <div className="loading">
            {message}
        </div>
    );
}
