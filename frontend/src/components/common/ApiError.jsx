import { toUserFriendlyError } from '../../utils/errorMessages';

/**
 * ApiError Component
 * Displays user-friendly error messages (never raw backend errors).
 */
export default function ApiError({ error, endpoint, onRetry }) {
    const message = toUserFriendlyError(error);
    return (
        <div className="error-box">
            <strong>Error:</strong> {message}
            {endpoint && (
                <p style={{ marginTop: '0.5rem', fontSize: '0.875rem', opacity: 0.8 }}>
                    Endpoint: {endpoint}
                </p>
            )}
            {onRetry && (
                <button
                    type="button"
                    className="primary"
                    style={{ marginTop: '0.75rem' }}
                    onClick={onRetry}
                >
                    Try Again
                </button>
            )}
        </div>
    );
}
