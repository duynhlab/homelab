/**
 * ApiDebug Component
 * Standardized API response debug display (only shown in development)
 * 
 * Usage:
 *   <ApiDebug data={orders} />
 *   <ApiDebug data={{ order, shipment }} label="Order Details" />
 */
export default function ApiDebug({ data, label = 'API Response' }) {
    // Only render in development mode
    if (!import.meta.env.DEV) {
        return null;
    }

    return (
        <details className="api-debug">
            <summary>{label}</summary>
            <pre>{JSON.stringify(data, null, 2)}</pre>
        </details>
    );
}
