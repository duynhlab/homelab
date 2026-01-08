/**
 * ApiError Component
 * Displays API error messages
 * API-agnostic - just displays the error
 */
export default function ApiError({ error, endpoint }) {
    return (
        <div className="error-box">
            <strong>API Error:</strong> {error}
            {endpoint && (
                <p style={{ marginTop: '0.5rem', fontSize: '0.875rem', opacity: 0.8 }}>
                    Endpoint: {endpoint}
                </p>
            )}
        </div>
    );
}
